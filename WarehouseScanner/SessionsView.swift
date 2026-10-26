import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var lang: LangStore   // đổi ngôn ngữ thì làm mới màn hình
    @EnvironmentObject var store: AppStore
    @State private var sessions: [ReceivingSession] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showSettings = false
    @State private var showNew = false
    @State private var created: ReceivingSession?
    @State private var openCreated = false
    // Phiên công ty (thử, chỉ đọc): danh sách lấy từ API công ty; phiên được chọn chỉ ghi nhớ trên máy, chưa ghi gì lên công ty.
    @State private var coSessions: [CompanySession] = []
    @State private var coError: String?
    @State private var coLoading = false
    @State private var coCarriers: [Int: String] = [:]      // id hãng → tên hãng (API danh sách phiên chỉ trả id hãng)
    @State private var showCoNew = false
    @AppStorage("company.selectedSessionId") private var coSelectedId = 0
    @AppStorage("company.selectedSessionLabel") private var coSelectedLabel = ""

    var body: some View {
        List {
            if let error {
                Label(error, systemImage: "wifi.exclamationmark").foregroundStyle(Color.accent)
            }
            Section {
                if !CompanyAPI.shared.isSignedIn {
                    Text("Chưa đăng nhập công ty. Vào Cài đặt (bánh răng) → Kết nối công ty để đăng nhập.").foregroundStyle(.secondary)
                } else if let coError {
                    Label(coError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.accent)
                } else if coSessions.isEmpty && !coLoading {
                    Text("Công ty chưa có phiên nào đang mở.").foregroundStyle(.secondary)
                }
                ForEach(coSessions, id: \.id) { s in
                    NavigationLink {
                        CompanyTrackingsView(session: s, carrierName: coCarrierName(s))
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("#\(s.id)").font(.headline)
                                    Text(coCarrierName(s)).font(.subheadline).foregroundStyle(Color.accent)
                                }
                                Text(coDetail(s)).font(.caption).foregroundStyle(.secondary)
                                Text(coExtra(s)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(coCount(s)).font(.title3.monospacedDigit().bold())
                            if coSelectedId == s.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.okGreen) }
                        }
                    }
                }
                if CompanyAPI.shared.isSignedIn {
                    Button { showCoNew = true } label: { Label("Tạo phiên thử trên công ty (ghi)", systemImage: "plus.circle") }
                }
            } header: { Text("Phiên công ty đang mở (thử)") }
              footer: { Text(coSelectedId > 0 ? "Đang chọn \(coSelectedLabel). Chạm phiên để xem kiện. Chưa ghi gì lên công ty." : "Chạm một phiên để xem các kiện đã quét và chọn dùng thử. Chưa ghi gì lên công ty.") }

            Section(tr("Phiên đang mở trên web")) {
                if sessions.isEmpty && !loading {
                    Text(tr("Chưa có phiên nào đang mở. Hãy tạo phiên trên web (nút \"Bắt đầu phiên mới\"), rồi kéo xuống hoặc bấm ↻ để làm mới.")).foregroundStyle(.secondary)
                }
                ForEach(sessions) { s in
                    NavigationLink(value: s) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(s.title).font(.headline)
                                Text(s.carrierName).font(.subheadline).foregroundStyle(Color.accent)
                                Spacer()
                                Text("\(s.scannedCount) / \(s.totalExpectedPackages)").font(.title3.monospacedDigit().bold())
                            }
                            Text([s.licensePlate, s.driverName, s.gateCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay { if loading && sessions.isEmpty { ProgressView() } }
        .navigationTitle(tr("Phiên nhận hàng"))
        .navigationDestination(for: ReceivingSession.self) { SessionDetailView(session: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button { showSettings = true } label: { Image(systemName: "gearshape") } }
            ToolbarItem(placement: .topBarTrailing) { Button { Task { await load(); await loadCompany() } } label: { Image(systemName: "arrow.clockwise") } }
            ToolbarItem(placement: .topBarTrailing) { Button { showNew = true } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel(tr("Bắt đầu phiên mới")) }
        }
        .sheet(isPresented: $showSettings, onDismiss: { Task { await loadCompany() } }) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showCoNew, onDismiss: { Task { await loadCompany() } }) {
            NavigationStack { CompanyNewSessionView(carriers: coCarriers) }
        }
        .sheet(isPresented: $showNew, onDismiss: {
            if created != nil { openCreated = true }       // tạo xong → vào quét ngay (giống web)
        }) {
            NavigationStack { NewSessionView { s in created = s } }
        }
        .navigationDestination(isPresented: $openCreated) {
            if let s = created { SessionDetailView(session: s) }
        }
        .onChange(of: openCreated) { open in if !open { created = nil; Task { await load() } } }
        .task { await loadCompany(); await store.refresh(); await load(); _ = await PhotoOutbox.flush(api: store.api) }   // gửi bù ảnh label còn sót
        .refreshable { await load(); await loadCompany() }
    }

    /// Tên hãng của phiên: ưu tiên tên API trả kèm, rồi tra theo id trong danh sách hãng; không có thì hiện id.
    private func coCarrierName(_ s: CompanySession) -> String {
        if let n = s.carrier?.name, !n.isEmpty { return n }
        if let n = coCarriers[s.carrierId] { return n }
        return "hãng \(s.carrierId)"
    }

    /// Dòng mô tả một phiên công ty: cửa · người giao · biển số · loại xe.
    private func coDetail(_ s: CompanySession) -> String {
        var parts: [String] = []
        if let gate = s.dockGate, !gate.isEmpty { parts.append("cửa \(gate)") }
        if let driver = s.driverName, !driver.isEmpty { parts.append(driver) }
        if let plate = s.licensePlate, !plate.isEmpty { parts.append(plate) }
        if let type = s.vehicleType, !type.isEmpty { parts.append(type) }
        return parts.joined(separator: " · ")
    }

    /// Dòng phụ: trạm · giờ xe đến · người mở phiên.
    private func coExtra(_ s: CompanySession) -> String {
        var parts: [String] = []
        if let station = s.station?.code, !station.isEmpty { parts.append(station) }
        if let t = coTime(s.vehicleArrivedAt) { parts.append("xe đến " + t) }
        if let u = s.user {
            let name = (u.fullName ?? "").isEmpty ? u.username : (u.fullName ?? u.username)
            parts.append("mở bởi " + name)
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

    /// Chỉ đọc: GET receiving-sessions?status=OPEN. Lỗi của server cũ không ảnh hưởng mục này (và ngược lại).
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
            coError = error.localizedDescription
        }
    }

    private func load() async {
        guard store.hasServer else { return }
        loading = true
        defer { loading = false }
        do { sessions = try await store.api.openSessions(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - Kiện của phiên công ty (chỉ đọc)

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
    case "CHECKED_IN": return "Đã nhập"
    case "ON_HOLD": return "Đang giữ"
    case "CONSOLIDATED": return "Đã gom thùng"
    case "CHECKED_OUT": return "Đã xuất"
    case "ARRIVED_GATEWAY_VN": return "Đã đến cổng VN"
    case "RETURNED_TO_SELLER": return "Trả người bán"
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
                        Text(coSelectedId == session.id ? "Đang dùng phiên này" : "Chọn dùng phiên này")
                    }
                }
                HStack {
                    Text("Đã quét / hãng khai").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(session.actualScannedCount ?? 0) / " + (session.carrierReportedCount.map(String.init) ?? "—")).monospacedDigit().bold()
                }
            } footer: { Text("Chỉ xem. Chưa ghi gì lên công ty.") }

            Section {
                TextField("Gõ hoặc dán mã tracking", text: $checkCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button {
                    Task { await runCheck() }
                } label: {
                    HStack {
                        Text("Kiểm tra mã (không ghi)")
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
            } header: { Text("Kiểm tra mã với công ty") }
              footer: { Text("Chỉ hỏi công ty mã này đã có chưa, không tạo kiện.") }

            if session.status == "OPEN" {
                Section {
                    NavigationLink {
                        AutoScanView(session: ReceivingSession(id: session.id, carrierName: carrierName, driverName: session.driverName,
                                                               licensePlate: session.licensePlate, gateCode: session.dockGate, status: "OPEN",
                                                               totalExpectedPackages: session.carrierReportedCount ?? 0,
                                                               scannedCount: session.actualScannedCount ?? 0),
                                     company: CompanyScanTarget(sessionId: session.id, carrierId: session.carrierId))
                    } label: {
                        Label("Quét vào phiên này (ghi lên công ty)", systemImage: "viewfinder").foregroundStyle(Color.accent)
                    }
                } footer: { Text("Mỗi kiện quét ở đây là kiện THẬT trên công ty, không xoá được. Lần đầu chỉ quét 1 kiện rồi đối chiếu với web.") }
            }

            Section("Kiện trong phiên") {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.accent)
                } else if items.isEmpty && !loading {
                    Text("Phiên này chưa có kiện nào.").foregroundStyle(.secondary)
                }
                ForEach(items) { t in
                    NavigationLink { CompanyTrackingDetailView(tracking: t) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(t.trackingNumber).font(.subheadline.monospaced().bold()).lineLimit(1)
                                Spacer()
                                if t.matchStatus == "NO_NAME" {
                                    Text("NO NAME").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2), in: Capsule())
                                }
                            }
                            Text([coStatusText(t.status), t.customerCode.map { "khách \($0)" }, t.binLocation.map { "kệ \($0)" }, coFormatTime(t.checkedInAt)]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onAppear { if t.id == items.last?.id { Task { await loadMore() } } }
                }
                if loading { HStack { Spacer(); ProgressView(); Spacer() } }
            }
        }
        .navigationTitle("Phiên #\(session.id)")
        .navigationBarTitleDisplayMode(.inline)
        .task { if items.isEmpty { await reload() } }
        .refreshable { await reload() }
    }

    private func checkStatusText(_ s: String) -> String {
        switch s {
        case "FOUND": return "FOUND — có trong danh sách đơn"
        case "NOT_FOUND": return "NOT_FOUND — không có trong danh sách (sẽ là NO NAME)"
        case "DUPLICATE": return "DUPLICATE — đã quét rồi"
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

    var body: some View {
        let t = tracking
        List {
            Section("Kiện") {
                row("Tracking", t.trackingNumber)
                if !t.additionalTrackingNumbers.isEmpty { row("Mã phụ", t.additionalTrackingNumbers.joined(separator: ", ")) }
                row("Trạng thái", coStatusText(t.status))
                row("Khớp đơn", t.matchStatus == "NO_NAME" ? "NO NAME (không có trong danh sách)" : (t.matchStatus == "MATCHED" ? "Khớp" : (t.matchStatus ?? "—")))
                row("Khách", t.customerCode ?? "—")
                row("Vị trí kệ", t.binLocation ?? "—")
                row("Tình trạng", t.condition == "DAMAGED" ? "Hư hỏng" : (t.condition == "NORMAL" ? "Bình thường" : (t.condition ?? "—")))
                row("Check-in", coFormatTime(t.checkedInAt))
                row("Ảnh label", "\(t.labelPhotoCount) ảnh")
            }
            Section("Số lượng") {
                row("Số dòng hàng", coQty(t.orderItemCount))
                row("Khai báo", coQty(t.totalQuantity))
                row("Thực nhận", coQty(t.totalActualQuantity))
                row("Hư hỏng", coQty(t.totalDamagedQuantity))
            }
            if !t.orderItems.isEmpty {
                Section("Hàng trong kiện") {
                    ForEach(Array(t.orderItems.enumerated()), id: \.offset) { _, it in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(it.itemName ?? it.itemId ?? "—").font(.subheadline.bold())
                            Text("Đơn \(it.clientOrderId ?? "—") · khai \(coQty(it.quantity)) · nhận \(coQty(it.actualQuantity)) · hỏng \(coQty(it.damagedQuantity))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !t.holdCases.isEmpty {
                Section("Giữ hàng") {
                    ForEach(Array(t.holdCases.enumerated()), id: \.offset) { _, h in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(h.reasonName ?? "—").font(.subheadline.bold())
                            Text(h.resolvedAt == nil ? "Chưa xử lý" : "Đã xử lý \(coFormatTime(h.resolvedAt))" + (h.resolution.map { " · \($0)" } ?? ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let error { Section { Text(error).foregroundStyle(Color.accent) } }
        }
        .navigationTitle("Chi tiết kiện")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
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
    }
}

// MARK: - Tạo phiên thử trên công ty (GHI, không xoá được)

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
                Picker("Hãng", selection: $carrierId) {
                    Text("Chọn hãng").tag(0)
                    ForEach(sortedCarriers, id: \.id) { Text($0.name).tag($0.id) }
                }
                TextField("Cửa kho", text: $gate).textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField("Người giao", text: $driver)
                TextField("Số kiện hãng khai", text: $count).keyboardType(.numberPad)
            } footer: { Text("Tạo phiên THẬT trên apiwh-dev. Không xoá được, nên chỉ tạo một phiên.") }
            if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.accent) } }
            Section {
                if done {
                    Label("Đã tạo phiên #\(createdId)", systemImage: "checkmark.circle.fill").foregroundStyle(Color.okGreen)
                } else {
                    Button {
                        confirm = true
                    } label: {
                        HStack { Spacer(); if saving { ProgressView() }; Text(saving ? "Đang tạo…" : "Tạo phiên thử").font(.headline); Spacer() }
                    }
                    .disabled(saving || carrierId == 0 || driver.trimmingCharacters(in: .whitespaces).isEmpty || Int(count) == nil)
                }
            }
        }
        .navigationTitle("Tạo phiên thử")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(done ? "Đóng" : "Huỷ") { dismiss() } } }
        .alert("Tạo phiên trên công ty?", isPresented: $confirm) {
            Button("Huỷ", role: .cancel) {}
            Button("Tạo") { Task { await create() } }
        } message: { Text("Sẽ ghi một phiên thật lên apiwh-dev và không xoá được.") }
    }

    private func create() async {
        guard !saving, !done else { return }
        saving = true; error = nil
        defer { saving = false }
        do {
            let me = try await CompanyAPI.shared.me()
            guard let station = me.stations.first else {
                error = "Tài khoản không có trạm nào"; return
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
