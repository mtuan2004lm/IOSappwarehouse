import SwiftUI
import AudioToolbox

/// Một dòng trong lịch sử quét.
struct ScanEntry: Identifiable {
    enum Status { case sent, noWarehouseCode, noBarcode, duplicate, rejected, tracked, noName }
    let id = UUID()
    let barcode: String
    var warehouseText: String?
    var group: String?
    var status: Status
    var note: String?
    let time = Date()
}

/// Kết quả hiển thị lớn trên màn hình: nhãn này thuộc kho / nhóm khách hàng nào.
struct LastResult: Equatable {
    let barcode: String
    let group: String?          // kho / nhóm khách hàng (nil nếu bỏ qua)
    let warehouseText: String?  // mã kho đọc được trên nhãn
    let message: String?
    var businessType: String? = nil   // KINH_DOANH | KHONG_KINH_DOANH (từ server)
    var duplicate: Bool = false // true: nhãn đã quét trước đó trong phiên -> MÃ TRÙNG
    var failed: Bool = false    // true: đọc được mã kho nhưng không đọc được mã vạch -> FAIL
    var unknown: Bool = false   // true: mã không có trong Danh sách mặt hàng -> "Không xác định"
    var track: Int? = nil       // 1...3: tracking chưa có thông tin ("ting"), chờ tracking tiếp theo hoặc END CODE
    var noName: Bool = false    // true: quét END CODE -> kiện NO NAME (tracking đầu làm tracking gốc)
    var company: Bool = false   // true: kết quả quét vào phiên công ty (hiện thẻ riêng)
    var noWarehouse: Bool = false // true: thấy mã vạch nhưng chưa đọc được mã kho -> yêu cầu đưa tem vào lại
    var endBlocked: Bool = false // true: đã đủ 3 tracking không có thông tin mà vẫn quét tiếp -> bị chặn
}

/// QUÉT TỰ ĐỘNG: mỗi nhãn chỉ cần đưa vào khung một lần.
/// App lấy cùng lúc mã vạch + dòng mã kho (OCR) trong cùng một "cửa sổ" ~3,5 giây rồi tự gửi về web.
/// Nhãn nào không đọc đủ (thiếu mã kho) thì bỏ qua, không hỏi gì, không chặn quét nhãn tiếp theo.
/// App không phân loại kinh doanh / không kinh doanh: chỉ hiện nhãn thuộc kho nào.
@MainActor
final class AutoScanViewModel: ObservableObject {
    @Published var sent = 0
    @Published var failed = 0
    @Published var skipped = 0
    @Published var queued = 0                 // đang chờ gửi lại do mất mạng
    @Published var reading = false
    @Published var progress: Double = 0       // 0...1 của cửa sổ đọc
    @Published var entries: [ScanEntry] = []
    @Published var last: LastResult?
    @Published var lastItem: ScannedItem?     // kiện gửi thành công gần nhất (để gắn ảnh hỏng nếu cần)
    @Published var banner: String?
    @Published var pendingTracks = 0          // số tracking chưa có thông tin của tem đang quét (0...3)
    @Published var endRequired = false        // true: bắt buộc quét QR END CODE (pop-up chặn)
    @Published var ocrDebug = ""            // các dòng chữ OCR đang đọc (hiện nhỏ trên màn quét để biết app đọc ra gì)
    @Published var hint: String?              // lý do app đang im lặng (vd. tem đã quét rồi) để không tưởng app hỏng
    private var hintTask: Task<Void, Never>?

    let session: ReceivingSession
    var matcher = RuleMatcher(rules: [])

    /// Thời gian tối đa gom đủ barcode + mã kho cho một nhãn (mục tiêu ~2 giây).
    let window: TimeInterval = 2.5

    private struct Pending {
        var barcode: String?
        var extras: [String] = []            // các mã vạch khác cùng đọc được trên tem (tối đa 3 mã tracking / tem)
        var warehouse: (text: String, group: String)?
        let start: Date
    }
    private var pending: Pending?
    private var recentMatch: (text: String, group: String, at: Date)?
    private var done = Set<String>()                      // mã đã gửi (hoặc đang gửi) -> không gửi lại
    private var skippedAt: [String: Date] = [:]           // mã đã bị bỏ qua, để không đếm lặp
    private var cooldown: [String: Date] = [:]
    private var lastSeen: [String: Date] = [:]           // lần cuối thấy mỗi mã vạch (để phân biệt "vẫn nằm trong khung" với "quét lại")
    private var lastDupAt: [String: Date] = [:]          // lần cuối báo MÃ TRÙNG cho mã này
    private var suppressTextUntil = Date.distantPast     // nhãn đã gửi vẫn đang trong khung -> không coi chữ mã kho là nhãn mới
    private var failCooldown: [String: Date] = [:]        // mã kho đã báo FAIL -> không báo lặp khi nhãn vẫn nằm trong khung
    private var retryList: [(code: String, text: String, group: String)] = []
    private var endCodeAt: Date?
    private var noKhoMiss: [String: Date] = [:]            // mã vạch đã bị báo THIẾU MÃ KHO một lần (lần thứ hai thì gửi không kèm mã kho)
    private var lastLabel: (text: String, group: String)?     // mã kho của tem đang quét (dùng cho các tracking tiếp theo của cùng tem)
    private var timerTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    /// Phiên công ty đang quét (ghi thật lên apiwh-dev).
    let company: CompanyScanTarget
    private var coPending: [String] = []       // tracking chưa có thông tin của tem đang quét (tối đa 3, chỉ lưu trong bộ nhớ)
    private var coPendingText = ""             // mã kho của tem đang quét

    init(session: ReceivingSession, company: CompanyScanTarget) { self.session = session; self.company = company }

    func stop() {
        timerTask?.cancel()
        retryTask?.cancel()
        retryTask = nil
    }

    // MARK: Đầu vào từ camera

    /// QR "END CODE" (mã cố định dùng chung): kết thúc tem khi cả 3 tracking đều không có thông tin.
    static func isEndCode(_ s: String) -> Bool {
        // Chỉ nhận đúng "ENDCODE" (tem Code 39 *ENDCODE*), không còn nhận "END CODE" / "END-CODE" / "END_CODE"
        return s.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "*")).uppercased() == "ENDCODE"   // Code 39 có thể trả kèm dấu * start/stop
    }

    /// Nút END CODE trên màn hình (thay cho việc quét mã END CODE): chốt các tracking đang chờ.
    func endCode() {
        guard pendingTracks > 0 else { return }
        if let t = endCodeAt, Date().timeIntervalSince(t) < 1.5 { return }     // chống bấm đúp
        endCodeAt = Date()
        clearPending()
        Haptics.tick()
        Task { await send(code: "ENDCODE", text: lastLabel?.text ?? "", group: "") }
    }

    private func showHint(_ text: String) {
        guard hint == nil else { return }
        hint = text
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled { self?.hint = nil }
        }
    }

    func handle(barcodes: [String]) {
        let now = Date()
        // Trong khung có tem MỚI (chưa gửi) không? Nếu có thì tem cũ còn sót một phần không được nuốt chữ mã kho của tem mới
        let hasNew = barcodes.contains { raw in
            let c = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return !c.isEmpty && !Self.isEndCode(c) && !done.contains(c)
        }
        for raw in barcodes {
            let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { continue }
            if Self.isEndCode(code) {
                if let t = endCodeAt, now.timeIntervalSince(t) < 3 { continue }
                endCodeAt = now
                clearPending()
                Task { await send(code: "ENDCODE", text: lastLabel?.text ?? "", group: "") }   // không cần đọc mã kho
                continue
            }
            let prevSeen = lastSeen[code]
            lastSeen[code] = now
            if done.contains(code) {
                // Nhãn đã gửi rồi. Nếu nó vẫn nằm trong khung thì im lặng; nếu đã rời khung rồi quét lại -> MÃ TRÙNG (không phải FAIL)
                if !hasNew {
                    suppressTextUntil = now.addingTimeInterval(2)
                    if pending != nil, pending?.barcode == nil { clearPending() }      // chữ mã kho của nhãn này, không phải nhãn mới
                }
                if let p = prevSeen, now.timeIntervalSince(p) > 0.7,
                   lastDupAt[code].map({ now.timeIntervalSince($0) > 4 }) ?? true {
                    lastDupAt[code] = now
                    Task { await send(code: code, text: code, group: "") }          // server trả 409 -> hiện MÃ TRÙNG, web tăng bộ đếm
                } else if !hasNew {
                    showHint(tr("Tem này đã quét rồi — đưa ra khỏi khung rồi đưa lại để báo trùng"))
                }
                continue
            }
            if let f = failCooldown[code], now.timeIntervalSince(f) < 8 { showHint(tr("Tem này vừa báo lỗi — đợi vài giây rồi đưa lại")); continue }   // vừa báo FAIL, đừng báo lặp
            if let t = cooldown[code], now.timeIntervalSince(t) < 1.5 { continue }

            suppressTextUntil = .distantPast      // tem mới vào khung: chữ mã kho của nó không được bị chặn
            // Tem cũ đã rời khung mà chưa có mã kho: chốt ngay, không bắt tem mới chờ hết cửa sổ đọc
            if let pb = pending?.barcode, pb != code, !barcodes.contains(pb), pending?.warehouse == nil { expire() }
            if pending == nil {
                begin(Pending(barcode: code, warehouse: nil, start: now))
            } else if pending?.barcode == nil {
                pending?.barcode = code
            } else if pending?.barcode != code {
                // Mã khác trong cùng khung hình = mã tracking khác trên cùng tem: gom lại, chỉ cần 1 mã có trong danh sách là nhận
                if let p = pending, !p.extras.contains(code), p.extras.count < 4,
                   barcodes.contains(p.barcode ?? "") { pending?.extras.append(code) }
                continue
            }
            // Các mã khác đang nằm cùng khung hình với mã này
            if var p = pending, p.barcode == code {
                for other in barcodes {
                    let o = other.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !o.isEmpty, o != code, !Self.isEndCode(o), !done.contains(o), !p.extras.contains(o), p.extras.count < 4 { p.extras.append(o) }
                }
                pending = p
            }
            // Mã kho có thể đã đọc được vài khung hình trước khi thấy mã vạch
            if pending?.warehouse == nil, let r = recentMatch, now.timeIntervalSince(r.at) < 3.0 {
                pending?.warehouse = (text: r.text, group: r.group)
            }
            tryComplete()
            return
        }
    }

    func handle(lines: [String]) {
        let shown = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(6).joined(separator: " | ")
        if !shown.isEmpty, shown != ocrDebug { ocrDebug = shown }
        guard let hit = matcher.firstMatch(inLines: lines) else { return }
        let now = Date()
        if now < suppressTextUntil { return }                                      // nhãn đã gửi vẫn trong khung
        if let t = failCooldown[hit.text], now.timeIntervalSince(t) < 8 { return }   // nhãn vừa báo FAIL, đừng báo lặp
        let m = (text: hit.text, group: hit.rule.customerGroup)
        recentMatch = (text: m.text, group: m.group, at: now)
        lastLabel = m
        if pending == nil {
            begin(Pending(barcode: nil, warehouse: m, start: now))
        } else if pending?.warehouse == nil {
            pending?.warehouse = m
        }
        tryComplete()
    }

    // MARK: Cửa sổ đọc một nhãn

    private func begin(_ p: Pending) {
        pending = p
        reading = true
        progress = 0
        timerTask?.cancel()
        let start = p.start
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(start)
                self.progress = min(elapsed / self.window, 1)
                if elapsed >= self.window { self.expire(); return }
            }
        }
    }

    private func clearPending() {
        timerTask?.cancel()
        pending = nil
        reading = false
        progress = 0
        recentMatch = nil
    }

    private func tryComplete() {
        guard let p = pending, let code = p.barcode, let w = p.warehouse else { return }
        // Chờ thêm một chút để các mã khác trên cùng tem kịp vào khung (gửi cả nhóm một lần, tối đa 3 mã)
        let wait = 0.5 - Date().timeIntervalSince(p.start)
        if p.extras.count < 2 && wait > 0 {
            Task { [weak self] in try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)); self?.tryComplete() }
            return
        }
        clearPending()
        submit(code: code, text: w.text, group: w.group, extras: p.extras)
    }

    /// Hết thời gian mà vẫn thiếu một trong hai -> bỏ qua, không hỏi gì.
    private func expire() {
        let p = pending
        clearPending()
        // Đọc được mã kho nhưng không có mã vạch -> FAIL (báo lên web, không tạo kiện)
        if p?.barcode == nil, let w = p?.warehouse {
            reportFail(text: w.text, group: w.group)
            return
        }
        // Có mã vạch nhưng chưa đọc được mã kho: vẫn gửi tracking (không bỏ sót ting / yes); mã kho lấy của tem đang quét nếu có
        guard let p, let code = p.barcode, p.warehouse == nil else { return }
        // Tracking tiếp theo của cùng tem đang quét: dùng mã kho của tem đó
        if pendingTracks > 0, let l = lastLabel {
            submit(code: code, text: l.text, group: l.group, extras: p.extras)
            return
        }
        // Tem mới mà chưa đọc được mã kho: lần đầu cảnh báo THIẾU MÃ KHO (chưa gửi) để đưa tem vào lại; lần hai gửi không kèm mã kho
        if let t = noKhoMiss[code], Date().timeIntervalSince(t) < 60 {
            noKhoMiss[code] = nil
            submit(code: code, text: "", group: "", extras: p.extras)
            return
        }
        noKhoMiss[code] = Date()
        cooldown[code] = Date().addingTimeInterval(1.5)       // đợi ~3 giây rồi mới đọc lại
        last = LastResult(barcode: code, group: nil, warehouseText: nil, message: "Chưa đọc được mã kho — đưa tem vào lại (chưa gửi lên công ty)", noWarehouse: true)
        Haptics.warning()
        AudioServicesPlaySystemSound(1053)
    }

    /// Đọc được mã kho nhưng chưa thấy mã vạch: không báo FAIL, chỉ nhắc nhẹ để đưa mã vạch vào khung.
    private func reportFail(text: String, group: String) {
        failCooldown[text] = Date()
        showHint(tr("Chưa thấy mã vạch — đưa mã vạch vào khung"))
    }

    // MARK: Gửi về web

    private func submit(code: String, text: String, group: String, extras: [String] = []) {
        done.insert(code)                      // chặn gửi lặp ngay lập tức
        cooldown[code] = Date()
        for x in extras { done.insert(x); cooldown[x] = Date() }
        Task { await send(code: code, text: text, group: group, extras: extras) }
    }

    /// Gửi MỘT tracking. `extras` = các mã khác cùng thấy trên tem: nếu tracking này "ting" (chưa có thông tin) thì gửi tiếp
    /// mã kế tiếp theo thứ tự (tracking 2, 3); nếu đã "yes" hoặc NO NAME thì bỏ qua các mã còn lại (cùng một kiện).
    private func send(code: String, text: String, group: String, extras: [String] = []) async {
        await sendCompany(company, code: code, text: text, group: group, extras: extras)
    }

    // MARK: Quét vào phiên công ty (GHI thật)

    /// Theo quy trình Phần 1 (Scan tracking):
    ///  - Tracking có thông tin ("yes", âm thanh) → ghi 1 kiện; các tracking trước đó chưa có thông tin trở thành mã phụ của kiện.
    ///  - Tracking chưa có thông tin → "ting", chờ tracking tiếp theo. Đủ 3 mà vẫn quét tiếp → chặn, bắt buộc quét END CODE.
    ///  - END CODE → cả 3 không có thông tin: lấy tracking đầu làm tracking gốc, ghi kiện NO NAME (2 mã còn lại là mã phụ).
    /// Mỗi mã vạch được cắt thành các mã ứng viên (TrackingCutter) rồi hỏi công ty lần lượt.
    private func sendCompany(_ co: CompanyScanTarget, code: String, text: String, group: String, extras: [String]) async {
        let customer = (text.isEmpty || text == code) ? "" : text
        do {
            if code == "ENDCODE" {
                guard let first = coPending.first else {
                    banner = tr("Chưa có tracking nào đang chờ — không cần END CODE")
                    endRequired = false; pendingTracks = 0
                    Task { try? await Task.sleep(nanoseconds: 3_000_000_000); banner = nil }
                    return
                }
                let wh = coPendingText.isEmpty ? customer : coPendingText
                let r = try await CompanyAPI.shared.scan(trackingNumber: first, additional: Array(coPending.dropFirst()),
                                                         carrierId: co.carrierId, customerCode: wh, sessionId: co.sessionId)
                coPending = []; pendingTracks = 0; endRequired = false
                sent += 1
                lastItem = companyItem(r.id, co, barcode: first, wh: wh, noName: true)
                let note = "NO NAME · \(r.checkIn)" + (wh.isEmpty ? " · không có mã kho" : " · mã kho \(wh)")
                entries.insert(ScanEntry(barcode: first, warehouseText: wh.isEmpty ? nil : wh, status: .noName, note: note), at: 0)
                last = LastResult(barcode: first, group: nil, warehouseText: wh.isEmpty ? nil : wh, message: note, noName: true)
                Haptics.warning(); AudioServicesPlaySystemSound(1103)
                return
            }
            let cut = TrackingCutter.candidates(code)
            if coPending.contains(cut.primary) { return }          // cùng một tem vẫn nằm trong khung
            if coPending.count >= 3 {
                done.remove(code)
                for x in extras { done.remove(x) }
                endRequired = true; pendingTracks = 3
                last = LastResult(barcode: code, group: nil, warehouseText: nil, message: "Bắt buộc bấm nút END CODE", endBlocked: true)
                Haptics.warning(); AudioServicesPlaySystemSound(1053)
                return
            }
            // Hỏi công ty lần lượt từng mã ứng viên; gặp FOUND / DUPLICATE thì dừng
            // Hỏi song song tất cả mã ứng viên (nhanh hơn hỏi lần lượt), rồi chọn mã đứng trước trong danh sách
            var results: [Int: String] = [:]
            try await withThrowingTaskGroup(of: (Int, String).self) { group in
                for (i, v) in cut.list.enumerated() {
                    group.addTask { (i, try await CompanyAPI.shared.checkTracking(code: v).status) }
                }
                for try await (i, st) in group { results[i] = st }
            }
            var status = "NOT_FOUND"
            var value = cut.primary
            for i in cut.list.indices {
                if let st = results[i], st == "FOUND" || st == "DUPLICATE" { status = st; value = cut.list[i]; break }
            }
            switch status {
            case "DUPLICATE":
                skipped += 1
                entries.insert(ScanEntry(barcode: value, warehouseText: customer.isEmpty ? nil : customer, status: .duplicate, note: tr("Đã quét trước đó")), at: 0)
                last = LastResult(barcode: value, group: nil, warehouseText: nil, message: tr("Mã đã quét trong phiên"), duplicate: true)
                Haptics.warning(); AudioServicesPlaySystemSound(1053)
            case "FOUND":
                let r = try await CompanyAPI.shared.scan(trackingNumber: value, additional: coPending, carrierId: co.carrierId,
                                                         customerCode: customer, sessionId: co.sessionId)
                let usedPending = coPending.count
                coPending = []; pendingTracks = 0; endRequired = false
                if r.checkIn == "DUPLICATE" {
                    skipped += 1
                    entries.insert(ScanEntry(barcode: value, warehouseText: nil, status: .duplicate, note: tr("Đã quét trước đó")), at: 0)
                    last = LastResult(barcode: value, group: nil, warehouseText: nil, message: tr("Mã đã quét trong phiên"), duplicate: true)
                    Haptics.warning(); AudioServicesPlaySystemSound(1053)
                } else {
                    sent += 1
                    lastItem = companyItem(r.id, co, barcode: value, wh: customer, noName: r.matchStatus == "NO_NAME")
                    let note = r.matchStatus + (usedPending > 0 ? " · +\(usedPending) mã phụ" : "") + (customer.isEmpty ? " · không có mã kho" : " · mã kho \(customer)")
                    entries.insert(ScanEntry(barcode: value, warehouseText: customer.isEmpty ? nil : customer, status: r.matchStatus == "NO_NAME" ? .noName : .sent, note: note), at: 0)
                    last = LastResult(barcode: value, group: nil, warehouseText: customer.isEmpty ? nil : customer, message: note, company: true)
                    Haptics.success(); AudioServicesPlaySystemSound(1057)
                }
            default:    // NOT_FOUND: chưa có thông tin → "ting"
                coPending.append(cut.primary)
                if !customer.isEmpty { coPendingText = customer }
                let seq = coPending.count
                pendingTracks = seq
                let needEnd = seq >= 3
                if needEnd { endRequired = true }
                let msg = needEnd ? "Đủ 3 tracking — bấm nút END CODE" : tr("Tracking {0}/3 chưa có thông tin", seq)
                let tried = "Công ty không có mã này. Đã thử: " + cut.list.prefix(3).joined(separator: ", ")
                entries.insert(ScanEntry(barcode: cut.primary, warehouseText: customer.isEmpty ? nil : customer, status: .tracked, note: msg + " · " + tried), at: 0)
                last = LastResult(barcode: cut.primary, group: nil, warehouseText: nil, message: tried, track: seq)
                Haptics.warning(); AudioServicesPlaySystemSound(1103)
                if let next = extras.first { await sendCompany(co, code: next, text: text, group: group, extras: Array(extras.dropFirst())) }
            }
        } catch let e as CompanyError {
            if e.status == 0 {
                enqueue(code: code, text: text, group: group)     // mất mạng: tự gửi lại (lệnh quét an toàn khi gửi lại)
            } else {
                done.remove(code)
                for x in extras { done.remove(x) }
                skipped += 1
                entries.insert(ScanEntry(barcode: code, warehouseText: customer, status: .rejected, note: e.localizedDescription), at: 0)
                last = LastResult(barcode: code, group: nil, warehouseText: customer, message: e.localizedDescription)
                Haptics.error()
            }
        } catch {
            enqueue(code: code, text: text, group: group)
        }
    }

    /// Kiện công ty vừa ghi, để gắn ảnh label (nút "Ảnh label").
    private func companyItem(_ id: String, _ co: CompanyScanTarget, barcode: String, wh: String, noName: Bool) -> ScannedItem? {
        guard !id.isEmpty else { return nil }
        return ScannedItem(id: FlexID(id), sessionId: co.sessionId, barcode: barcode, detectedWarehouseCode: wh.isEmpty ? nil : wh,
                           customerGroup: nil, businessType: nil, exceptionStatus: "", isNoName: noName)
    }

    /// Mất mạng: giữ lại và tự gửi lại mỗi 4 giây, không làm mất kiện nào.
    private func enqueue(code: String, text: String, group: String) {
        retryList.append((code: code, text: text, group: group))
        queued = retryList.count
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self else { return }
                if self.retryList.isEmpty { self.queued = 0; self.retryTask = nil; return }
                let batch = self.retryList
                self.retryList = []
                for item in batch { await self.send(code: item.code, text: item.text, group: item.group) }
                self.queued = self.retryList.count
            }
        }
    }

    // MARK: Ảnh label (gắn vào kiện vừa gửi; nhân viên VN kiểm duyệt trên web)

    func uploadLabelPhoto(_ image: UIImage, for item: ScannedItem) async {
        guard let jpeg = image.resized(maxSide: 1600).jpegData(compressionQuality: 0.7) else { return }
        do {
            try await CompanyAPI.shared.uploadLabelPhoto(trackingId: item.id.value, jpeg: jpeg)
            banner = tr("Đã gửi ảnh label cho {0}", item.barcode)
        } catch {
            banner = tr("Gửi ảnh label thất bại: {0}", error.localizedDescription)
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        banner = nil
    }
}
