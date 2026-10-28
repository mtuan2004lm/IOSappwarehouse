import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var lang: LangStore   // đổi ngôn ngữ thì làm mới màn hình
    @EnvironmentObject var auth: AuthStore
    @State private var showSettings = false
    // Phiên công ty: danh sách lấy từ API công ty.
    @State private var coSessions: [CompanySession] = []
    @State private var coError: String?
    @State private var coLoading = false
    @State private var coCarriers: [Int: String] = [:]      // id hãng → tên hãng (API danh sách phiên chỉ trả id hãng)
    @State private var showCoNew = false
    @AppStorage("company.selectedSessionId") private var coSelectedId = 0
    @AppStorage("company.selectedSessionLabel") private var coSelectedLabel = ""

    var body: some View {
        List {
            Section {
                if !CompanyAPI.shared.isSignedIn {
                    Text(tr("Chưa đăng nhập công ty.")).foregroundStyle(.secondary)
                } else if let coError {
                    Label(coError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.accent)
                } else if coSessions.isEmpty && !coLoading {
                    Text(tr("Công ty chưa có phiên nào đang mở.")).foregroundStyle(.secondary)
                }
                ForEach(coSessions, id: \.id) { s in
                    NavigationLink {
                        CompanyTrackingsView(session: s, carrierName: coCarrierName(s))
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("#\(s.id)").font(.title3.bold())
                                    Text(coCarrierName(s)).font(.headline).foregroundStyle(Color.accent)
                                }
                                Text(coDetail(s)).font(.subheadline).foregroundStyle(.secondary)
                                Text(coExtra(s)).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(coCount(s)).font(.title2.monospacedDigit().bold())
                            if coSelectedId == s.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.okGreen) }
                        }
                    }
                }
            } header: { Text(tr("Phiên đang mở")) }
              footer: { Text(coSelectedId > 0 ? tr("Đang chọn {0}. Chạm phiên để xem kiện và quét.", coSelectedLabel) : tr("Chạm một phiên để xem các kiện đã quét và bắt đầu quét.")) }

        }
        .overlay { if coLoading && coSessions.isEmpty { ProgressView() } }
        .navigationTitle(tr("Phiên nhận hàng"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button { showSettings = true } label: { Image(systemName: "gearshape") } }
            ToolbarItem(placement: .topBarTrailing) { Button { Task { await loadCompany() } } label: { Image(systemName: "arrow.clockwise") } }
            ToolbarItem(placement: .topBarTrailing) { Button { showCoNew = true } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel(tr("Tạo phiên mới")) }
        }
        .sheet(isPresented: $showSettings, onDismiss: { Task { await loadCompany() } }) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showCoNew, onDismiss: { Task { await loadCompany() } }) {
            NavigationStack { CompanyNewSessionView(carriers: coCarriers) }
        }
        .onAppear { Task { await loadCompany() } }      // mỗi lần quay lại màn này (vd. sau khi kết thúc phiên) tải lại danh sách
        .refreshable { await loadCompany() }
    }

    /// Tên hãng của phiên: ưu tiên tên API trả kèm, rồi tra theo id trong danh sách hãng; không có thì hiện id.
    private func coCarrierName(_ s: CompanySession) -> String {
        if let n = s.carrier?.name, !n.isEmpty { return n }
        if let n = coCarriers[s.carrierId] { return n }
        return tr("hãng {0}", s.carrierId)
    }

    /// Dòng mô tả một phiên công ty: cửa · người giao · biển số · loại xe.
    private func coDetail(_ s: CompanySession) -> String {
        var parts: [String] = []
        if let gate = s.dockGate, !gate.isEmpty { parts.append(tr("cửa {0}", gate)) }
        if let driver = s.driverName, !driver.isEmpty { parts.append(driver) }
        if let plate = s.licensePlate, !plate.isEmpty { parts.append(plate) }
        if let type = s.vehicleType, !type.isEmpty { parts.append(type) }
        return parts.joined(separator: " · ")
    }

    /// Dòng phụ: trạm · giờ xe đến · người mở phiên.
    private func coExtra(_ s: CompanySession) -> String {
        var parts: [String] = []
        if let station = s.station?.code, !station.isEmpty { parts.append(station) }
        if let t = coTime(s.vehicleArrivedAt) { parts.append(tr("xe đến ") + t) }
        if let u = s.user {
            let name = (u.fullName ?? "").isEmpty ? u.username : (u.fullName ?? u.username)
            parts.append(tr("mở bởi ") + name)
        }
        return parts.joined(separator: " · ")
    }

    /// "đã quét / hãng khai" giống web (vd 6 / 20).
    private func coCount(_ s: CompanySession) -> String {
        let scanned = s.actualScannedCount ?? 0
        guard let reported = s.carrierReportedCount else { return "\(scanned)" }
        return "\(scanned) / \(reported)"
    }

    /// Đổi chuỗi giờ ISO của API sang giờ máy: dd/MM HH:mm.
    private func coTime(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let withMs = ISO8601DateFormatter()
        withMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let d = withMs.date(from: iso) ?? plain.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "dd/MM HH:mm"
        return out.string(from: d)
    }

    /// GET receiving-sessions?status=OPEN.
    private func loadCompany() async {
        guard CompanyAPI.shared.isSignedIn else { coSessions = []; coError = nil; return }
        coLoading = true
        defer { coLoading = false }
        do {
            if coCarriers.isEmpty, let cs = try? await CompanyAPI.shared.carriers() {
                coCarriers = Dictionary(cs.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            }
            let list = try await CompanyAPI.shared.openSessions()
            coSessions = list.sorted { $0.id > $1.id }
            coError = nil
        } catch {
            if let e = error as? CompanyError, e.status == 401 { auth.signOut(); return }   // hết hạn đăng nhập → về màn đăng nhập
            coError = error.localizedDescription
        }
    }
}

// MARK: - Kiện của phiên công ty (chỉ đọc)

/// Tên hàng/đơn đã liên kết, vd "Kem chống nắng Anessa Perfect UV 60ml (đơn 990001)"; chưa có tên thì ghi "Khớp".
private func coMatchedText(_ t: CompanyTracking) -> String {
    let names = t.orderItems.compactMap { it -> String? in
        guard let n = it.itemName ?? it.itemId else { return nil }
        return it.clientOrderId.map { "\(n) (\(tr("đơn")) \($0))" } ?? n
    }
    return names.isEmpty ? tr("Khớp") : names.joined(separator: ", ")
}

private func coFormatTime(_ iso: String?) -> String {
    guard let iso, !iso.isEmpty else { return "—" }
    let withMs = ISO8601DateFormatter()
    withMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    guard let d = withMs.date(from: iso) ?? plain.date(from: iso) else { return iso }
    let out = DateFormatter()
    out.dateFormat = "dd/MM HH:mm"
    return out.string(from: d)
}

private func coQty(_ v: Double?) -> String {
    guard let v else { return "—" }
    return v == v.rounded() ? String(Int(v)) : String(v)
}

private func coStatusText(_ s: String?) -> String {
    switch s {
    case "CHECKED_IN": return tr("Đã nhập")
    case "ON_HOLD": return tr("Đang giữ")
    case "CONSOLIDATED": return tr("Đã gom thùng")
    case "CHECKED_OUT": return tr("Đã xuất")
    case "ARRIVED_GATEWAY_VN": return tr("Đã đến cổng VN")
    case "RETURNED_TO_SELLER": return tr("Trả người bán")
    default: return s ?? "—"
    }
}

struct CompanyTrackingsView: View {
    let session: CompanySession
    let carrierName: String
    @AppStorage("company.selectedSessionId") private var coSelectedId = 0
    @AppStorage("company.selectedSessionLabel") private var coSelectedLabel = ""
    @State private var items: [CompanyTracking] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var error: String?
    @State private var checkCode = ""
    @State private var checking = false
    @State private var checkStatus: String?
    @State private var checkDetail = ""
    @State private var checkError: String?
    @State private var confirmClose = false        // hỏi xác nhận trước khi đóng phiên trên công ty
    @State private var closing = false
    @State private var closedNow = false           // vừa đóng xong trong lần xem này
    @State private var closeError: String?
    @Environment(\.dismiss) private var dismiss
    private let pageSize = 30

    var body: some View {
        List {
            Section {
                Button {
                    coSelectedId = session.id
                    coSelectedLabel = "#\(session.id) " + carrierName
                    Haptics.tick()
                } label: {
                    HStack {
                        Image(systemName: coSelectedId == session.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(coSelectedId == session.id ? Color.okGreen : .secondary)
                        Text(coSelectedId == session.id ? tr("Đang dùng phiên này") : tr("Chọn dùng phiên này"))
                    }
                }
                HStack {
                    Text(tr("Đã quét / hãng khai")).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(session.actualScannedCount ?? 0) / " + (session.carrierReportedCount.map(String.init) ?? "—")).monospacedDigit().bold()
                }
            } footer: { Text(tr("Chỉ xem. Chưa ghi gì lên công ty.")) }

            Section {
                TextField(tr("Gõ hoặc dán mã tracking"), text: $checkCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button {
                    Task { await runCheck() }
                } label: {
                    HStack {
                        Text(tr("Kiểm tra mã (không ghi)"))
                        if checking { Spacer(); ProgressView() }
                    }
                }
                .disabled(checking || checkCode.trimmingCharacters(in: .whitespaces).isEmpty)
                if let checkError {
                    Label(checkError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.accent)
                } else if let checkStatus {
                    Text(checkStatusText(checkStatus)).font(.headline)
                    if !checkDetail.isEmpty { Text(checkDetail).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            } header: { Text(tr("Kiểm tra mã với công ty")) }
              footer: { Text(tr("Chỉ hỏi công ty mã này đã có chưa, không tạo kiện.")) }

            if session.status == "OPEN" && !closedNow {
                Section {
                    NavigationLink {
                        AutoScanView(session: ReceivingSession(id: session.id, carrierName: carrierName, driverName: session.driverName,
                                                               licensePlate: session.licensePlate, gateCode: session.dockGate, status: "OPEN",
                                                               totalExpectedPackages: session.carrierReportedCount ?? 0,
                                                               scannedCount: session.actualScannedCount ?? 0),
                                     company: CompanyScanTarget(sessionId: session.id, carrierId: session.carrierId))
                    } label: {
                        Label(tr("Quét vào phiên này"), systemImage: "viewfinder").foregroundStyle(Color.accent)
                    }
                } footer: { Text(tr("Mỗi kiện quét ở đây là kiện THẬT trên công ty, không xoá được. Lần đầu chỉ quét 1 kiện rồi đối chiếu với web.")) }

                Section {
                    Button(role: .destructive) { confirmClose = true } label: {
                        HStack {
                            Label(tr("Kết thúc phiên"), systemImage: "checkmark.seal")
                            if closing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(closing)
                } footer: { Text(tr("Đóng phiên trên công ty: không quét thêm vào phiên này được.")) }
            }

            Section(tr("Kiện trong phiên")) {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.accent)
                } else if items.isEmpty && !loading {
                    Text(tr("Phiên này chưa có kiện nào.")).foregroundStyle(.secondary)
                }
                ForEach(items) { t in
                    NavigationLink { CompanyTrackingDetailView(tracking: t) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            // Mã dài: ăn hết chiều ngang dòng riêng, tự thu nhỏ chữ cho vừa 1 dòng (không cắt "…", không rớt dòng)
                            Text(t.trackingNumber).font(.subheadline.monospaced().bold())
                                .lineLimit(1).minimumScaleFactor(0.5).allowsTightening(true)
                            HStack(spacing: 6) {
                                if t.isUnknown {
                                    Text(tr("Kiện không xác định")).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2), in: Capsule())
                                }
                                if t.condition == "DAMAGED" {
                                    Text(tr("HƯ HỎNG")).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.dupRed.opacity(0.25), in: Capsule())
                                }
                                Text([coStatusText(t.status), t.customerCode.map { tr("khách {0}", $0) }, t.binLocation.map { tr("kệ {0}", $0) }, coFormatTime(t.checkedInAt)]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    .onAppear { if t.id == items.last?.id { Task { await loadMore() } } }
                }
                if loading { HStack { Spacer(); ProgressView(); Spacer() } }
            }
        }
        .navigationTitle(tr("Phiên #{0}", session.id))
        .navigationBarTitleDisplayMode(.inline)
        .task { if items.isEmpty { await reload() } }
        .refreshable { await reload() }
        .alert(tr("Kết thúc phiên?"), isPresented: $confirmClose) {
            Button(tr("Huỷ"), role: .cancel) {}
            Button(tr("Kết thúc phiên"), role: .destructive) { Task { await closeSession() } }
        } message: { Text(tr("Phiên #{0} sẽ được đóng trên công ty, không quét thêm vào phiên này được. Đã quét {1} kiện.", session.id, session.actualScannedCount ?? items.count)) }
        .alert(tr("Không đóng được phiên"), isPresented: Binding(get: { closeError != nil }, set: { if !$0 { closeError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(closeError ?? "") }
    }

    /// GHI lên công ty: đóng phiên (PATCH status=CLOSED). Xong thì quay về danh sách phiên (danh sách tự tải lại).
    private func closeSession() async {
        guard !closing else { return }
        closing = true
        defer { closing = false }
        do {
            try await CompanyAPI.shared.closeSession(id: session.id)
            closedNow = true
            if coSelectedId == session.id { coSelectedId = 0; coSelectedLabel = "" }      // phiên đã đóng thì bỏ chọn
            Haptics.success()
            dismiss()
        } catch {
            closeError = error.localizedDescription
        }
    }

    private func checkStatusText(_ s: String) -> String {
        switch s {
        case "FOUND": return tr("FOUND — có trong danh sách đơn")
        case "NOT_FOUND": return tr("NOT_FOUND — không có trong danh sách (sẽ là kiện không xác định)")
        case "DUPLICATE": return tr("DUPLICATE — đã quét rồi")
        default: return s
        }
    }

    private func runCheck() async {
        let code = checkCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        checking = true
        defer { checking = false }
        do {
            let r = try await CompanyAPI.shared.checkTracking(code: code)
            checkStatus = r.status; checkDetail = r.detail; checkError = nil
        } catch {
            checkStatus = nil; checkDetail = ""; checkError = error.localizedDescription
        }
    }

    private func reload() async {
        items = []; page = 1; hasMore = true; error = nil
        await loadMore()
    }

    private func loadMore() async {
        guard hasMore, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let got = try await CompanyAPI.shared.trackings(sessionId: session.id, page: page, limit: pageSize)
            let known = Set(items.map(\.id))
            items += got.filter { !known.contains($0.id) }
            hasMore = got.count >= pageSize
            page += 1
            error = nil
        } catch {
            self.error = error.localizedDescription
            hasMore = false
        }
    }
}

struct CompanyTrackingDetailView: View {
    @State var tracking: CompanyTracking
    @State private var error: String?
    @State private var viewer: PhotoViewerItem?
    @State private var damage: CompanyDamageReport?
    @State private var damageNote: String?      // lý do chưa lấy được báo cáo hư hỏng

    var body: some View {
        let t = tracking
        List {
            Section(tr("Kiện")) {
                row("Tracking", t.trackingNumber)
                if !t.additionalTrackingNumbers.isEmpty { row(tr("Mã phụ"), t.additionalTrackingNumbers.joined(separator: ", ")) }
                row(tr("Trạng thái"), coStatusText(t.status))
                rowStacked(tr("Khớp đơn"), t.isUnknown ? tr("Kiện không xác định (không có trong danh sách)") : ((t.matchStatus == "MATCHED" || t.hasOrderLines) ? coMatchedText(t) : (t.matchStatus ?? "—")))
                row(tr("Khách"), t.customerCode ?? "—")
                row(tr("Vị trí kệ"), t.binLocation ?? "—")
                row(tr("Tình trạng"), t.condition == "DAMAGED" ? tr("Hư hỏng") : (t.condition == "NORMAL" ? tr("Bình thường") : (t.condition ?? "—")))
                row("Check-in", coFormatTime(t.checkedInAt))
                row(tr("Ảnh label"), tr("{0} ảnh", t.labelPhotoCount))
            }
            if !t.labelPhotoURLs.isEmpty {
                Section(tr("Ảnh label đã chụp")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(t.labelPhotoURLs.enumerated()), id: \.offset) { i, s in
                                Button { viewer = PhotoViewerItem(urls: t.labelPhotoURLs, start: i) } label: {
                                    RemotePhoto(urlString: s, fill: true)
                                        .frame(width: 110, height: 110)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Text(tr("Chạm vào ảnh để xem lớn, chụm hai ngón để phóng to.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if t.condition == "DAMAGED" {
                Section(tr("Ảnh báo hư hỏng")) {
                    if let d = damage {
                        if let at = d.reportedAt { row(tr("Đã báo lúc"), coFormatTime(at)) }
                        row(tr("Loại hư hỏng"), d.typeNames.isEmpty ? "—" : d.typeNames.joined(separator: ", "))
                        row(tr("Quyết định"), d.decision == "RECEIVED" ? tr("Nhận hàng") : (d.decision == "REJECTED" ? tr("Từ chối") : (d.decision ?? "—")))
                        if d.photoURLs.isEmpty {
                            Text(tr("Công ty chưa có ảnh hư hỏng cho kiện này.")).font(.caption).foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(d.photoURLs.enumerated()), id: \.offset) { i, s in
                                        Button { viewer = PhotoViewerItem(urls: d.photoURLs, start: i) } label: {
                                            RemotePhoto(urlString: s, fill: true)
                                                .frame(width: 110, height: 110)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } else if let n = damageNote {
                        Text(tr("Chưa lấy được báo cáo hư hỏng: {0}", n)).font(.caption).foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
            }
            Section(tr("Số lượng")) {
                row(tr("Số dòng hàng"), coQty(t.orderItemCount))
                row(tr("Khai báo"), coQty(t.totalQuantity))
                row(tr("Thực nhận"), coQty(t.totalActualQuantity))
                row(tr("Hư hỏng"), coQty(t.totalDamagedQuantity))
            }
            if !t.orderItems.isEmpty {
                Section(tr("Hàng trong kiện")) {
                    ForEach(Array(t.orderItems.enumerated()), id: \.offset) { _, it in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(it.itemName ?? it.itemId ?? "—").font(.subheadline.bold())
                            Text(tr("Đơn {0} · khai {1} · nhận {2} · hỏng {3}", it.clientOrderId ?? "—", coQty(it.quantity), coQty(it.actualQuantity), coQty(it.damagedQuantity)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !t.holdCases.isEmpty {
                Section(tr("Giữ hàng")) {
                    ForEach(Array(t.holdCases.enumerated()), id: \.offset) { _, h in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(h.reasonName ?? "—").font(.subheadline.bold())
                            Text(h.resolvedAt == nil ? tr("Chưa xử lý") : tr("Đã xử lý {0}", coFormatTime(h.resolvedAt)) + (h.resolution.map { " · \($0)" } ?? ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let error { Section { Text(error).foregroundStyle(Color.accent) } }
        }
        .navigationTitle(tr("Chi tiết kiện"))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewer) { PhotoViewer(item: $0) }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    /// Nhãn nằm trên, giá trị nằm dưới ăn hết chiều ngang và to hơn: đọc được trọn tên hàng dài.
    private func rowStacked(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k).font(.subheadline).foregroundStyle(.secondary)
            Text(v).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }

    /// Danh sách chưa chắc kèm đủ hàng/hold; lấy bản chi tiết (chỉ đọc) để bổ sung.
    private func refresh() async {
        do { tracking = try await CompanyAPI.shared.tracking(id: tracking.id); error = nil }
        catch { self.error = error.localizedDescription }
        await loadDamage()
    }

    /// Kiện hư hỏng: lấy báo cáo hư hỏng để xem lại ảnh (chỉ đọc).
    private func loadDamage() async {
        guard tracking.condition == "DAMAGED" else { return }
        do {
            damage = try await CompanyAPI.shared.damageReport(trackingId: tracking.id)
            damageNote = nil
        } catch {
            damageNote = error.localizedDescription
        }
    }
}

// MARK: - Tạo phiên trên công ty (GHI, không xoá được)

struct CompanyNewSessionView: View {
    let carriers: [Int: String]
    @Environment(\.dismiss) private var dismiss
    @State private var carrierId = 0
    @State private var gate = ""
    @State private var driver = ""
    @State private var count = ""
    @State private var saving = false
    @State private var confirm = false
    @State private var done = false
    @State private var error: String?
    @State private var createdId = 0

    private var sortedCarriers: [(id: Int, name: String)] {
        carriers.map { (id: $0.key, name: $0.value) }.sorted { $0.id < $1.id }
    }

    var body: some View {
        Form {
            Section {
                Picker(tr("Hãng"), selection: $carrierId) {
                    Text(tr("Chọn hãng")).tag(0)
                    ForEach(sortedCarriers, id: \.id) { Text($0.name).tag($0.id) }
                }
                TextField(tr("Cửa kho"), text: $gate).textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField(tr("Người giao"), text: $driver)
                TextField(tr("Số kiện hãng khai"), text: $count).keyboardType(.numberPad)
            } footer: { Text(tr("Tạo phiên THẬT trên apiwh-dev. Không xoá được, nên chỉ tạo một phiên.")) }
            if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.accent) } }
            Section {
                if done {
                    Label(tr("Đã tạo phiên #{0}", createdId), systemImage: "checkmark.circle.fill").foregroundStyle(Color.okGreen)
                } else {
                    Button {
                        confirm = true
                    } label: {
                        HStack { Spacer(); if saving { ProgressView() }; Text(saving ? tr("Đang tạo…") : tr("Tạo phiên")).font(.headline); Spacer() }
                    }
                    .disabled(saving || carrierId == 0 || driver.trimmingCharacters(in: .whitespaces).isEmpty || Int(count) == nil)
                }
            }
        }
        .navigationTitle(tr("Tạo phiên"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(done ? tr("Đóng") : tr("Huỷ")) { dismiss() } } }
        .alert(tr("Tạo phiên?"), isPresented: $confirm) {
            Button(tr("Huỷ"), role: .cancel) {}
            Button(tr("Tạo")) { Task { await create() } }
        } message: { Text(tr("Sẽ ghi một phiên thật lên apiwh-dev và không xoá được.")) }
    }

    private func create() async {
        guard !saving, !done else { return }
        saving = true; error = nil
        defer { saving = false }
        do {
            let me = try await CompanyAPI.shared.me()
            guard let station = me.stations.first else {
                error = tr("Tài khoản không có trạm nào"); return
            }
            createdId = try await CompanyAPI.shared.createSession(stationId: station.id, carrierId: carrierId,
                                                                  driverName: driver.trimmingCharacters(in: .whitespaces),
                                                                  reportedCount: Int(count) ?? 0,
                                                                  dockGate: gate.trimmingCharacters(in: .whitespaces))
            done = true
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
    }
}


// MARK: - Xem ảnh (ảnh tem / ảnh hư hỏng) từ link của công ty

struct PhotoViewerItem: Identifiable {
    let id = UUID()
    let urls: [String]
    let start: Int
}

/// Tải một ảnh từ link; hiện vòng xoay khi đang tải, biểu tượng lỗi nếu không mở được.
struct RemotePhoto: View {
    let urlString: String
    var fill = false
    var body: some View {
        AsyncImage(url: URL(string: urlString)) { phase in
            switch phase {
            case .success(let img):
                if fill { img.resizable().scaledToFill() } else { img.resizable().scaledToFit() }
            case .failure:
                ZStack { Color.gray.opacity(0.2); Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary) }
            default:
                ZStack { Color.gray.opacity(0.15); ProgressView() }
            }
        }
    }
}

/// Xem ảnh toàn màn hình: vuốt ngang đổi ảnh, chụm để phóng to, chạm đúp để về cỡ gốc, nút X để đóng.
struct PhotoViewer: View {
    let item: PhotoViewerItem
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(item: PhotoViewerItem) { self.item = item; _index = State(initialValue: item.start) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(item.urls.enumerated()), id: \.offset) { i, s in
                    ZoomablePhoto(urlString: s).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: item.urls.count > 1 ? .automatic : .never))
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 34)).foregroundStyle(.white, .black.opacity(0.6))
            }
            .padding(16)
        }
        .preferredColorScheme(.dark)
    }
}

struct ZoomablePhoto: View {
    let urlString: String
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragBase: CGSize = .zero

    var body: some View {
        RemotePhoto(urlString: urlString)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { scale = min(max(base * $0, 1), 6) }
                    .onEnded { _ in base = scale; if scale <= 1 { offset = .zero; dragBase = .zero } }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { if scale > 1 { offset = CGSize(width: dragBase.width + $0.translation.width, height: dragBase.height + $0.translation.height) } }
                    .onEnded { _ in dragBase = offset }
            )
            .onTapGesture(count: 2) { withAnimation { scale = 1; base = 1; offset = .zero; dragBase = .zero } }
    }
}
