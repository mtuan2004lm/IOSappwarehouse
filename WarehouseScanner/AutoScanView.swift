import SwiftUI

/// Màn hình quét duy nhất: đưa nhãn vào khung một lần, app tự lấy mã vạch + mã kho và gửi về web.
/// Chỉ hiển thị nhãn thuộc kho nào; không hỏi xác nhận, nhãn không đọc được thì tự bỏ qua.
struct AutoScanView: View {
    @EnvironmentObject var lang: LangStore   // đổi ngôn ngữ thì làm mới màn hình
    let session: ReceivingSession
    var company: CompanyScanTarget? = nil      // khác nil: quét vào phiên công ty (ghi thật)
    @EnvironmentObject var store: AppStore
    @StateObject private var camera = CameraEngine()
    @StateObject private var vm: AutoScanViewModel
    @State private var showPhoto = false
    @State private var photoTarget: ScannedItem?
    @State private var photoIsLabel = false      // true: ảnh label · false: ảnh báo hỏng
    @State private var showHistory = false
    @State private var showDamage = false          // phiên công ty: bảng báo hư hỏng
    @Environment(\.dismiss) private var dismiss
    @State private var paused = false              // đã dừng quét (chốt kiện)
    @State private var confirmStop = false
    @State private var confirmClose = false
    @State private var working = false
    @State private var actionError: String?
    @State private var finalCount = 0
    @State private var serverScanned: Int?        // số đã quét theo server (cập nhật ~1 giây như web)

    init(session: ReceivingSession, company: CompanyScanTarget? = nil) {
        self.session = session
        self.company = company
        let model = AutoScanViewModel(session: session)
        model.company = company
        _vm = StateObject(wrappedValue: model)
    }

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session).ignoresSafeArea()
            Color.black.opacity(0.2).ignoresSafeArea().allowsHitTesting(false)

            // Bố cục: [ĐÃ GỬI to] → [thẻ kết quả] → [khung quét co giãn] → [back + BỎ QUA] → [nút chức năng]
            // Phần trên/dưới cao cố định, khung quét ăn phần còn lại nên iPhone Pro và Pro Max trông giống nhau.
            VStack(spacing: 12) {
                sentCounter
                resultCard
                    .frame(height: 200, alignment: .top)       // chừa chỗ cố định để khung quét không nhảy mỗi lần quét
                ZStack(alignment: .top) {
                    Reticle(active: vm.reading, progress: vm.progress).allowsHitTesting(false)
                    VStack(spacing: 6) {
                        if vm.queued > 0 {
                            Label(tr("Mất kết nối, đang tự gửi lại ({0} nhãn chờ)", vm.queued), systemImage: "arrow.triangle.2.circlepath")
                                .font(.footnote.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.accent.opacity(0.9), in: Capsule())
                        }
                        if vm.photosPending > 0 {
                            Label(tr("{0} ảnh label đang chờ gửi", vm.photosPending), systemImage: "photo.on.rectangle.angled")
                                .font(.footnote.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.black.opacity(0.6), in: Capsule())
                        }
                        if let b = vm.banner {
                            Text(b).font(.footnote.bold()).padding(8).background(.ultraThinMaterial, in: Capsule())
                        }
                        if let h = vm.hint {
                            Text(h).font(.footnote.bold()).foregroundStyle(.white).multilineTextAlignment(.center)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.black.opacity(0.65), in: Capsule())
                        }
                    }
                    .padding(.top, 10).padding(.horizontal, 20)
                }
                .frame(maxHeight: .infinity)
                if vm.pendingTracks > 0 {
                    // Nút END CODE: chốt các tracking chưa có thông tin (to, dễ bấm bằng ngón cái)
                    Button { vm.endCode() } label: {
                        VStack(spacing: 2) {
                            Text("END CODE").font(.system(size: 24, weight: .heavy))
                            Text(vm.pendingTracks >= 3 ? "Bắt buộc bấm để chốt (3/3)" : "Bấm để chốt kiện ({0}/3)".replacingOccurrences(of: "{0}", with: String(vm.pendingTracks)))
                                .font(.footnote.bold())
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .foregroundStyle(.white)
                        .background(vm.pendingTracks >= 3 ? Color.dupRed : Color.accent, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 16)
                }
                bottomBar
                buttons
            }
            .padding(.top, 8)

            // Đã dừng quét: che camera, chỉ còn Tiếp tục / Kết thúc phiên
            if paused {
                ZStack {
                    Color.black.opacity(0.88).ignoresSafeArea()
                    VStack(spacing: 14) {
                        Image(systemName: "pause.circle.fill").font(.system(size: 56)).foregroundStyle(Color.accent)
                        Text(tr("ĐÃ DỪNG QUÉT")).font(.title2.weight(.heavy))
                        Text(tr("Đã chốt {0} kiện", finalCount)).font(.title3.bold()).foregroundStyle(Color.okGreen)
                        if let e = actionError { Text(e).font(.footnote).foregroundStyle(Color.accent).multilineTextAlignment(.center) }
                        Button { resumeScanning() } label: {
                            Text(tr("Tiếp tục quét")).font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent).tint(.accent)
                        Button(role: .destructive) { confirmClose = true } label: {
                            Text(tr("Kết thúc phiên")).font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.bordered)
                        Button(tr("Quay lại danh sách phiên")) { dismiss() }.foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white).padding(24).frame(maxWidth: 380)
                }
            }

            // Cảnh báo chặn: đủ 3 tracking không có thông tin -> bắt buộc bấm nút END CODE rồi mới quét tiếp
            if vm.endRequired {
                VStack {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34)).foregroundStyle(.yellow)
                        Text("BẮT BUỘC BẤM END CODE").font(.title3.weight(.heavy)).multilineTextAlignment(.center)
                        Text("Tem này đã quét đủ 3 tracking nhưng không có thông tin. Bấm nút END CODE bên dưới trước khi quét tem khác.")
                            .font(.footnote).multilineTextAlignment(.center).opacity(0.9)
                    }
                    .foregroundStyle(.white).padding(16)
                    .background(Color.dupRed.opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 24).padding(.top, 70)
                    Spacer()
                }
                .allowsHitTesting(false)      // không che nút END CODE phía dưới
            }

            if camera.authorized == false { PermissionDenied() }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { startScanning() }
        .task {
            // Đồng bộ số ĐÃ GỬI với server mỗi 1 giây (đơn xoá/thêm trên web hoặc máy khác cũng hiện ngay)
            while !Task.isCancelled {
                await pollServerCount()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        .onChange(of: vm.sent) { _ in Task { await pollServerCount() } }
        .onDisappear {
            vm.stop()
            camera.ocrEnabled = false
            camera.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .fullScreenCover(isPresented: $showPhoto, onDismiss: { startScanning() }) {
            PhotoPicker(onImage: { img in
                showPhoto = false
                if let item = photoTarget {
                    Task { if photoIsLabel { await vm.uploadLabelPhoto(img, for: item) } else { await vm.uploadDamagePhoto(img, for: item) } }
                }
            }, onCancel: { showPhoto = false })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showHistory) { HistorySheet(entries: vm.entries) }
        .sheet(isPresented: $showDamage, onDismiss: { startScanning() }) {
            if let item = photoTarget { CompanyDamageSheet(item: item) }
        }
        .alert(tr("Dừng quét và chốt kiện?"), isPresented: $confirmStop) {
            Button(tr("Huỷ"), role: .cancel) {}
            Button(tr("Dừng quét")) { Task { await stopScanning() } }
        } message: { Text(tr("Chốt số kiện của phiên = số đã quét ({0}).", vm.sent)) }
        .alert(tr("Kết thúc phiên?"), isPresented: $confirmClose) {
            Button(tr("Huỷ"), role: .cancel) {}
            Button(tr("Kết thúc"), role: .destructive) { Task { await closeSession() } }
        } message: { Text(tr("Sau khi kết thúc sẽ không quét thêm được.")) }
    }

    // MARK: Dừng quét / kết thúc phiên (giống web: "Chốt kiện - END CODE" và "Kết thúc phiên")

    private func stopScanning() async {
        working = true; actionError = nil
        defer { working = false }
        if company != nil {          // phiên công ty: chỉ dừng quét trên máy, không đổi gì trên công ty
            finalCount = vm.sent
            vm.stop(); camera.ocrEnabled = false; camera.stop()
            paused = true
            Haptics.success()
            return
        }
        do {
            let s = try await store.api.finalizeSession(id: session.id)
            finalCount = s.totalExpectedPackages
            vm.stop(); camera.ocrEnabled = false; camera.stop()
            paused = true
            Haptics.success()
        } catch {
            vm.banner = error.localizedDescription      // không dừng được thì vẫn tiếp tục quét
            Haptics.error()
        }
    }

    private func pollServerCount() async {
        if company != nil { return }
        if let d = try? await store.api.sessionDetail(id: session.id) { serverScanned = d.session.scannedCount }
    }

    private func resumeScanning() { paused = false; actionError = nil; startScanning() }

    private func closeSession() async {
        working = true
        defer { working = false }
        if company != nil { dismiss(); return }     // không đóng phiên công ty từ app
        do {
            _ = try await store.api.closeSession(id: session.id)
            Haptics.success()
            dismiss()
        } catch {
            if paused { actionError = error.localizedDescription } else { vm.banner = error.localizedDescription }
            Haptics.error()
        }
    }

    private func startScanning() {
        vm.api = company == nil ? store.api : nil
        vm.matcher = store.matcher
        vm.snapshotProvider = { [camera] in await camera.snapshot() }
        vm.photosPending = PhotoOutbox.count
        if vm.photosPending > 0 { vm.startPhotoFlush() }       // gửi bù ảnh còn sót từ lần quét trước
        camera.ocrEnabled = true                 // đọc cả mã vạch lẫn chữ mã kho trên cùng khung hình
        camera.onBarcodes = { codes in Task { @MainActor in vm.handle(barcodes: codes) } }
        camera.onTextLines = { lines in Task { @MainActor in vm.handle(lines: lines) } }
        camera.start()
        UIApplication.shared.isIdleTimerDisabled = true      // giữ màn hình luôn sáng
    }

    // MARK: Thành phần giao diện

    /// Ô ĐÃ GỬI to ở trên cùng.
    private var sentCounter: some View {
        VStack(spacing: 0) {
            Text(tr("ĐÃ GỬI")).font(.caption.bold()).tracking(1.5).foregroundStyle(.white.opacity(0.7))
            Text("\(serverScanned ?? vm.sent)").font(.system(size: 72, weight: .heavy, design: .monospaced)).foregroundStyle(Color.okGreen)
                .minimumScaleFactor(0.5).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.navy.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    /// Hàng dưới: nút quay lại + BỎ QUA (nhỏ).
    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.title3.bold()).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(Color.navy.opacity(0.9), in: Circle())
            }
            .accessibilityLabel(tr("Quay lại"))
            Spacer(minLength: 0)
            smallCounter(tr("BỎ QUA"), vm.skipped, .unknownGray)
            Menu {
                Button { confirmStop = true } label: { Label(tr("Dừng quét (chốt kiện)"), systemImage: "pause.circle") }
                Button(role: .destructive) { confirmClose = true } label: { Label(tr("Kết thúc phiên"), systemImage: "flag.checkered") }
            } label: {
                Image(systemName: "ellipsis").font(.title3.bold()).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(Color.navy.opacity(0.9), in: Circle())
            }
            .accessibilityLabel(tr("Dừng quét hoặc kết thúc phiên"))
        }
        .padding(.horizontal, 16)
    }

    private func smallCounter(_ title: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption.bold()).foregroundStyle(.white.opacity(0.75))
            Text("\(value)").font(.system(.body, design: .monospaced).weight(.bold)).foregroundStyle(color)
        }
        .padding(.horizontal, 12).frame(height: 34)
        .background(Color.navy.opacity(0.9), in: Capsule())
    }

    /// Mã dài không được rớt dòng: một dòng, tự thu nhỏ chữ; quá dài thì cắt phần giữa.
    private func codeText(_ code: String, _ font: Font = .system(.footnote, design: .monospaced)) -> some View {
        Text(shortCode(code)).font(font).lineLimit(1).minimumScaleFactor(0.5).opacity(0.92)
    }

    private func shortCode(_ c: String, max: Int = 40) -> String {
        guard c.count > max else { return c }
        let head = c.prefix(max / 2 - 1), tail = c.suffix(max / 2 - 2)
        return "\(head)…\(tail)"
    }

    @ViewBuilder private var resultCard: some View {
        if vm.reading {
            card(bg: Color.navy.opacity(0.92)) {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(tr("Đang đọc nhãn…")).font(.headline)
                }
            }
        } else if let r = vm.last {
            if let n = r.track {
                // Tracking chưa có thông tin: "ting"
                card(bg: Color.accent) {
                    VStack(spacing: 4) {
                        Text("TING").font(.system(size: 34, weight: .heavy))
                        Text(tr("Tracking {0}/3 chưa có thông tin", n)).font(.subheadline.bold())
                        codeText(r.barcode)
                        if let m = r.message { Text(m).font(.footnote).opacity(0.9).multilineTextAlignment(.center) }
                    }
                }
            } else if r.noName {
                card(bg: Color.purple) {
                    VStack(spacing: 4) {
                        Text("NO NAME").font(.system(size: 34, weight: .heavy))
                        Text(tr("Cả 3 tracking không có thông tin")).font(.subheadline.bold())
                        codeText(r.barcode)
                        Text(tr("Nên chụp ảnh label để nhân viên VN kiểm tra")).font(.footnote).opacity(0.9)
                    }
                }
            } else if r.endBlocked {
                card(bg: Color.dupRed) {
                    VStack(spacing: 4) {
                        Text("BẤM END CODE").font(.system(size: 30, weight: .heavy))
                        Text(r.message ?? "Bắt buộc bấm nút END CODE").font(.subheadline.bold()).multilineTextAlignment(.center)
                    }
                }
            } else if r.duplicate {
                // Quét lại nhãn đã quét trong phiên: MÃ TRÙNG (không phải FAIL)
                card(bg: Color.accent) {
                    VStack(spacing: 4) {
                        Text(tr("MÃ TRÙNG")).font(.system(size: 34, weight: .heavy))
                        Text(tr("Nhãn này đã quét trong phiên")).font(.subheadline.bold())
                        codeText(r.barcode)
                    }
                }
            } else if r.failed {
                // Không đọc được mã vạch (nhưng đọc được mã kho): FAIL, web cũng hiện FAIL
                card(bg: Color.dupRed) {
                    VStack(spacing: 4) {
                        Text("FAIL").font(.system(size: 34, weight: .heavy))
                        Text(r.message ?? tr("Không đọc được mã vạch")).font(.subheadline.bold()).multilineTextAlignment(.center)
                        if !r.barcode.isEmpty { codeText(r.barcode) }
                        if let g = r.group { Text(tr("KHO {0}", g)).font(.footnote).opacity(0.9) }
                        if let t = r.warehouseText { Text(t).font(.system(.title3, design: .monospaced).weight(.semibold)).lineLimit(1).minimumScaleFactor(0.5) }
                    }
                }
            } else if r.company {
                // Quét vào phiên công ty: hiện mã kho đã gửi và kết quả công ty trả về
                card(bg: Color.okGreen) {
                    VStack(spacing: 6) {
                        Text("SUCCESS").font(.headline.weight(.heavy))
                        codeText(r.barcode)
                        VStack(spacing: 4) {
                            infoRow(tr("MÃ KHO"), r.warehouseText ?? "—", mono: true)
                            if let m = r.message { Text(m).font(.footnote).opacity(0.9).multilineTextAlignment(.center) }
                        }
                    }
                }
            } else if let group = r.group {
                // Thành công: hiện riêng Nhóm KH, Mã kho, Loại hình (web cũng lưu và hiển thị riêng từng cột)
                card(bg: Color.okGreen) {
                    VStack(spacing: 6) {
                        Text("SUCCESS").font(.headline.weight(.heavy))
                        codeText(r.barcode)
                        VStack(spacing: 4) {
                            infoRow(tr("NHÓM KH"), group)
                            infoRow(tr("MÃ KHO"), r.warehouseText ?? "—", mono: true)
                            infoRow(tr("LOẠI HÌNH"), businessLabel(r.businessType))
                        }
                    }
                }
            } else {
                // Bỏ qua: hiện ngắn gọn, không cần bấm gì
                card(bg: Color.unknownGray) {
                    VStack(spacing: 2) {
                        Text(tr("BỎ QUA")).font(.headline.weight(.heavy))
                        codeText(r.barcode)
                        if let m = r.message { Text(m).font(.footnote).opacity(0.9) }
                    }
                }
            }
        }
    }

    private func infoRow(_ title: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption.bold()).opacity(0.85).frame(width: 84, alignment: .leading)
            Text(value).font(mono ? .system(.title3, design: .monospaced).weight(.bold) : .title3.weight(.bold))
                .minimumScaleFactor(0.6).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func businessLabel(_ t: String?) -> String {
        switch t {
        case "KINH_DOANH": return "Kinh doanh"
        case "KHONG_KINH_DOANH": return tr("Không kinh doanh")
        default: return "—"
        }
    }

    private func card<C: View>(bg: Color, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(bg, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .padding(.horizontal, 16)
    }

    private var buttons: some View {
        HStack(spacing: 14) {
            roundButton(camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill") { camera.toggleTorch() }
            Button {
                photoTarget = vm.lastItem
                photoIsLabel = true
                camera.stop()                    // nhả camera trước khi mở màn chụp ảnh
                showPhoto = true
            } label: {
                Label(tr("Ảnh label"), systemImage: "doc.viewfinder")
                    .font(.subheadline.bold()).lineLimit(1)
                    .padding(.horizontal, 14).frame(height: 48)
                    .background(vm.lastItem == nil ? Color.gray.opacity(0.6) : Color.navy.opacity(0.9), in: Capsule())
                    .foregroundStyle(.white)
            }
            .disabled(vm.lastItem == nil)
            Button {
                photoTarget = vm.lastItem
                photoIsLabel = false
                camera.stop()                    // nhả camera trước khi mở màn chụp ảnh
                if company != nil { showDamage = true } else { showPhoto = true }
            } label: {
                Label(tr("Hỏng"), systemImage: "camera.fill")
                    .font(.subheadline.bold()).lineLimit(1)
                    .padding(.horizontal, 14).frame(height: 48)
                    .background(vm.lastItem == nil ? Color.gray.opacity(0.6) : Color.dupRed, in: Capsule())
                    .foregroundStyle(.white)
            }
            .disabled(vm.lastItem == nil)
            roundButton("list.bullet") { showHistory = true }
        }
        .padding(.bottom, 16)
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).foregroundStyle(.white)
                .frame(width: 48, height: 48).background(Color.navy.opacity(0.88), in: Circle())
        }
    }
}


// MARK: - Báo hư hỏng của kiện (phiên công ty, GHI thật) — giống web: loại hư hỏng → ảnh → quyết định (cuối cùng)

struct CompanyDamageSheet: View {
    let item: ScannedItem
    @Environment(\.dismiss) private var dismiss
    @State private var types: [CompanyDamageType] = []
    @State private var selected: Set<String> = []
    @State private var photos: [UIImage] = []
    @State private var decision = "RECEIVED"           // RECEIVED = Nhận hàng · REJECTED = Từ chối
    @State private var loading = true
    @State private var saving = false
    @State private var showPicker = false
    @State private var confirm = false
    @State private var done = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(item.barcode).font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)

                    // 1. Loại hư hỏng (chọn được nhiều)
                    Text("Loại hư hỏng").font(.headline)
                    if loading { ProgressView() }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(types) { t in
                            Button {
                                if selected.contains(t.code) { selected.remove(t.code) } else { selected.insert(t.code) }
                                Haptics.tick()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: selected.contains(t.code) ? "checkmark.circle.fill" : "circle")
                                    Text(t.name).font(.subheadline).multilineTextAlignment(.leading).lineLimit(2).minimumScaleFactor(0.8)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 52)
                                .background(selected.contains(t.code) ? Color.accent.opacity(0.25) : Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected.contains(t.code) ? Color.accent : Color.clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // 2. Ảnh hư hỏng (tối đa 10)
                    HStack {
                        Text("Ảnh hư hỏng").font(.headline)
                        Spacer()
                        Button { showPicker = true } label: { Label("Chụp ảnh", systemImage: "camera") }
                            .buttonStyle(.bordered).disabled(photos.count >= 10)
                    }
                    if !photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(photos.indices, id: \.self) { i in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: photos[i]).resizable().scaledToFill().frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 10))
                                        Button { photos.remove(at: i) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.7)) }
                                            .padding(3)
                                    }
                                }
                            }
                        }
                    }

                    // 3. Quyết định — luôn nằm cuối cùng
                    Text("Quyết định").font(.headline)
                    Picker("Quyết định", selection: $decision) {
                        Text("Nhận hàng").tag("RECEIVED")
                        Text("Từ chối").tag("REJECTED")
                    }
                    .pickerStyle(.segmented)
                    if decision == "REJECTED" {
                        Text("Từ chối: kiện chuyển sang trả người bán. Kiện đã vào thùng thì công ty không cho từ chối.").font(.footnote).foregroundStyle(Color.accent)
                    }

                    if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.accent).font(.footnote) }
                    if done {
                        Label("Đã gửi báo cáo hư hỏng", systemImage: "checkmark.circle.fill").foregroundStyle(Color.okGreen).font(.headline)
                    } else {
                        Button { confirm = true } label: {
                            HStack { Spacer(); if saving { ProgressView() }; Text(saving ? "Đang gửi…" : "Gửi báo cáo").font(.headline); Spacer() }
                                .frame(minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent).tint(.accent)
                        .disabled(saving || selected.isEmpty)
                        if selected.isEmpty { Text("Chọn ít nhất một loại hư hỏng.").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Báo hư hỏng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(done ? "Đóng" : "Huỷ") { dismiss() } } }
            .task { await loadTypes() }
            .fullScreenCover(isPresented: $showPicker) {
                PhotoPicker(onImage: { img in photos.append(img); showPicker = false }, onCancel: { showPicker = false }).ignoresSafeArea()
            }
            .alert("Gửi báo cáo hư hỏng lên công ty?", isPresented: $confirm) {
                Button("Huỷ", role: .cancel) {}
                Button("Gửi") { Task { await send() } }
            } message: { Text("Mỗi kiện chỉ có một báo cáo, gửi xong không sửa được từ app.") }
        }
    }

    private func loadTypes() async {
        do { types = try await CompanyAPI.shared.damageTypes().sorted { $0.name < $1.name }; error = nil }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private func send() async {
        guard !saving, !done else { return }
        saving = true; error = nil
        defer { saving = false }
        let jpegs = photos.compactMap { $0.resized(maxSide: 1600).jpegData(compressionQuality: 0.7) }
        do {
            try await CompanyAPI.shared.reportDamage(trackingId: item.id.value, typeCodes: types.map(\.code).filter { selected.contains($0) },
                                                     decision: decision, photos: jpegs)
            done = true
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
    }
}
