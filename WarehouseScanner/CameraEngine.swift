import AVFoundation
import Vision
import UIKit
import CoreImage

/// Camera chạy liên tục. Cùng một luồng hình cho cả hai việc:
///  - Đọc barcode bằng AVCaptureMetadataOutput (nhanh, chạy trên chip chuyên dụng)
///  - Đọc chữ (mã kho in trên nhãn) bằng Vision, chỉ khi bật `ocrEnabled`, đọc nhanh (.fast) tối đa tốc độ máy cho phép, cứ 8 lần thì có 1 lần đọc kỹ (.accurate) để không bỏ sót chữ nhỏ.
final class CameraEngine: NSObject, ObservableObject,
                          AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()
    @Published private(set) var authorized: Bool? = nil     // nil = chưa hỏi
    @Published private(set) var torchOn = false

    /// Gọi trên main thread: danh sách mã vạch đang thấy trong khung hình.
    var onBarcodes: (([String]) -> Void)?
    /// Gọi trên main thread: các dòng chữ đọc được trong một khung hình.
    var onTextLines: (([String]) -> Void)?

    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let videoQueue = DispatchQueue(label: "camera.video")
    private var device: AVCaptureDevice?
    private var configured = false

    // Cờ dùng giữa nhiều luồng -> bảo vệ bằng lock
    private let lock = NSLock()
    private var _ocrEnabled = false
    private var _ocrBusy = false
    private var _lastOCR = Date.distantPast
    private var _ocrCount = 0
    private var _lastBarcodeAt = Date.distantPast      // lần cuối thấy mã vạch
    private var _lastTextAt = Date.distantPast         // lần cuối OCR thấy chữ (tem đang nằm trong khung)
    private var _lastRefocus = Date.distantPast
    private var _latest: CVPixelBuffer?                // khung hình mới nhất (để chụp ảnh label khi quét)
    private static let ciContext = CIContext()
    var ocrEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _ocrEnabled }
        set { lock.lock(); _ocrEnabled = newValue; lock.unlock() }
    }

    private static let barcodeTypes: [AVMetadataObject.ObjectType] = [
        .code128, .code39, .code93, .ean13, .ean8, .upce, .itf14, .interleaved2of5, .qr, .pdf417, .dataMatrix, .aztec,
    ]

    // MARK: Vòng đời

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.authorized = true }
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { self?.authorized = granted }
                if granted { self?.run() }
            }
        default:
            DispatchQueue.main.async { self.authorized = false }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func run() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured { self.configure() }
            if self.configured, !self.session.isRunning { self.session.startRunning() }
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 1080p: đủ nét để đọc chữ nhỏ trên nhãn mà vẫn nhẹ
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high

        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: cam), session.canAddInput(input) else { return }
        session.addInput(input)
        device = cam

        // Lấy nét liên tục: quan trọng để đọc nhanh khi liên tục đưa kiện mới vào
        if (try? cam.lockForConfiguration()) != nil {
            if cam.isFocusModeSupported(.continuousAutoFocus) { cam.focusMode = .continuousAutoFocus }
            if cam.isExposureModeSupported(.continuousAutoExposure) { cam.exposureMode = .continuousAutoExposure }
            if cam.isSmoothAutoFocusSupported { cam.isSmoothAutoFocusEnabled = false }   // lấy nét nhanh hơn
            // Nhãn luôn ở gần (15-40 cm): giới hạn tầm lấy nét gần để không "săn nét" ra xa -> nét nhanh hơn rõ rệt
            if cam.isAutoFocusRangeRestrictionSupported { cam.autoFocusRangeRestriction = .near }
            if cam.isLowLightBoostSupported { cam.automaticallyEnablesLowLightBoostWhenAvailable = true }
            cam.unlockForConfiguration()
        }

        let meta = AVCaptureMetadataOutput()
        if session.canAddOutput(meta) {
            session.addOutput(meta)
            meta.setMetadataObjectsDelegate(self, queue: .main)
            meta.metadataObjectTypes = Self.barcodeTypes.filter { meta.availableMetadataObjectTypes.contains($0) }
        }

        let video = AVCaptureVideoDataOutput()
        video.alwaysDiscardsLateVideoFrames = true
        video.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(video) { session.addOutput(video) }

        configured = true
    }

    func toggleTorch() {
        sessionQueue.async { [weak self] in
            guard let self, let cam = self.device, cam.hasTorch, (try? cam.lockForConfiguration()) != nil else { return }
            cam.torchMode = cam.torchMode == .on ? .off : .on
            let on = cam.torchMode == .on
            cam.unlockForConfiguration()
            DispatchQueue.main.async { self.torchOn = on }
        }
    }

    // MARK: Barcode

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        let codes = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        if !codes.isEmpty {
            lock.lock(); _lastBarcodeAt = Date(); lock.unlock()
            onBarcodes?(codes)
        }
    }

    // MARK: Chụp ảnh label (khung hình camera ngay lúc quét)

    /// JPEG của khung hình mới nhất (đã xoay đúng chiều, thu nhỏ cạnh dài ≤ 1280px). Chạy ở luồng nền.
    func snapshot() async -> Data? {
        await withCheckedContinuation { cont in
            videoQueue.async { [weak self] in
                guard let self else { cont.resume(returning: nil); return }
                self.lock.lock(); let buf = self._latest; self.lock.unlock()
                guard let buf else { cont.resume(returning: nil); return }
                let ci = CIImage(cvPixelBuffer: buf).oriented(.right)      // camera sau ở chế độ dọc
                guard let cg = Self.ciContext.createCGImage(ci, from: ci.extent) else { cont.resume(returning: nil); return }
                let jpeg = UIImage(cgImage: cg).resized(maxSide: 1280).jpegData(compressionQuality: 0.6)
                cont.resume(returning: jpeg)
            }
        }
    }

    // MARK: Tự lấy nét lại

    /// Tem đang nằm trong khung (OCR thấy chữ) nhưng >1,5 giây không đọc được mã vạch -> nhiều khả năng camera kẹt nét/phơi sáng
    /// (trước đây phải che camera để nó lấy nét lại). Kích hoạt lấy nét + đo sáng lại, tối đa mỗi 2 giây một lần.
    private func refocusIfStuck() {
        let now = Date()
        lock.lock()
        let stuck = now.timeIntervalSince(_lastTextAt) < 1.0
            && now.timeIntervalSince(_lastBarcodeAt) > 1.5
            && now.timeIntervalSince(_lastRefocus) > 2.0
        if stuck { _lastRefocus = now }
        lock.unlock()
        guard stuck else { return }
        sessionQueue.async { [weak self] in
            guard let cam = self?.device, (try? cam.lockForConfiguration()) != nil else { return }
            let center = CGPoint(x: 0.5, y: 0.5)
            if cam.isFocusPointOfInterestSupported { cam.focusPointOfInterest = center }
            if cam.isFocusModeSupported(.autoFocus) { cam.focusMode = .autoFocus }                 // lấy nét một lần ngay
            if cam.isExposurePointOfInterestSupported { cam.exposurePointOfInterest = center }
            if cam.isExposureModeSupported(.continuousAutoExposure) { cam.exposureMode = .continuousAutoExposure }
            cam.unlockForConfiguration()
            // Xong thì trở lại lấy nét liên tục
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
                guard (try? cam.lockForConfiguration()) != nil else { return }
                if cam.isFocusModeSupported(.continuousAutoFocus) { cam.focusMode = .continuousAutoFocus }
                cam.unlockForConfiguration()
            }
        }
    }

    // MARK: OCR

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let buf = CMSampleBufferGetImageBuffer(sampleBuffer) { lock.lock(); _latest = buf; lock.unlock() }
        lock.lock()
        // Không còn khoảng nghỉ giữa hai lần OCR: xong khung này là đọc ngay khung kế tiếp (nhanh ~2x)
        let allowed = _ocrEnabled && !_ocrBusy
        var accurate = false
        if allowed { _ocrBusy = true; _lastOCR = Date(); _ocrCount += 1; accurate = _ocrCount % 8 == 0 }
        lock.unlock()
        refocusIfStuck()
        guard allowed, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNRecognizeTextRequest { [weak self] req, _ in
            let lines = (req.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first }
                .filter { $0.confidence > 0.3 }
                .map { $0.string } ?? []
            if !lines.isEmpty {
                self?.lock.lock(); self?._lastTextAt = Date(); self?.lock.unlock()
                DispatchQueue.main.async { self?.onTextLines?(lines) }
            }
        }
        // Phần lớn khung hình đọc nhanh (.fast, ~vài chục ms) để ra kết quả sớm; 1/8 khung đọc kỹ cho chữ nhỏ/mờ
        request.recognitionLevel = accurate ? .accurate : .fast
        request.usesLanguageCorrection = false     // mã không phải từ điển, tránh bị "sửa" sai

        // Camera sau ở chế độ dọc: ảnh gốc xoay 90° -> .right
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right, options: [:])
        try? handler.perform([request])

        lock.lock(); _ocrBusy = false; lock.unlock()
    }
}
