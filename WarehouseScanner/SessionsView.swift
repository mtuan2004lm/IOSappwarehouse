import SwiftUI
import UIKit

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
    // Bộ lọc giống web: hãng · trạng thái · cửa · giờ xe đến
    @State private var fCarrier = 0               // 0 = tất cả
    @State private var fStatus = ""               // "" = tất cả · OPEN · CLOSED
    @State private var fGate = ""                 // "" = tất cả
    @State private var loadToken = UUID()         // chỉ nhận kết quả của lần tải mới nhất (đổi nhiều bộ lọc cùng lúc, vd "Xoá lọc", sẽ gọi API nhiều lần)
    @State private var knownGates: Set<String> = []   // các cửa đã thấy (lọc theo cửa thì danh sách trả về chỉ còn một cửa, nên nhớ lại để vẫn chọn được cửa khác)
    @State private var fFrom: Date?
    @State private var fTo: Date?
    @State private var showDates = false

    var body: some View {
        List {
            Section {
                filterBar
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            Section {
                if !CompanyAPI.shared.isSignedIn {
                    Text(tr("Chưa đăng nhập công ty.")).foregroundStyle(.secondary)
                } else if let coError {
                    Label(coError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.accent)
                } else if shown.isEmpty && !coLoading {
                    Text(tr("Không có phiên nào phù hợp.")).foregroundStyle(.secondary)
                }
                ForEach(shown, id: \.id) { s in
                    NavigationLink {
                        CompanyTrackingsView(session: s, carrierName: coCarrierName(s))
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("#\(s.id)").font(.title3.bold())
                                    CarrierLogo(name: coCarrierName(s), code: s.carrier?.code)
                                }
                                coInfoRows(s)
                            }
                            Spacer()
                            Text(coCount(s)).font(.system(size: 30, weight: .heavy).monospacedDigit())
                                .foregroundStyle(coCountColor(s)).lineLimit(1).minimumScaleFactor(0.6).layoutPriority(1)
                        }
                    }
                }
            }

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
        .sheet(isPresented: $showDates) { DateRangeSheet(from: $fFrom, to: $fTo) }
        .onChange(of: fStatus) { _ in Task { await loadCompany() } }
        .onChange(of: fCarrier) { _ in Task { await loadCompany() } }
        .onChange(of: fGate) { _ in Task { await loadCompany() } }
        .onChange(of: fFrom) { _ in Task { await loadCompany() } }
        .onChange(of: fTo) { _ in Task { await loadCompany() } }
        .onAppear { Task { await loadCompany() } }      // mỗi lần quay lại màn này (vd. sau khi kết thúc phiên) tải lại danh sách
        .refreshable { await loadCompany() }
    }

    /// Tên hãng của phiên: ưu tiên tên API trả kèm, rồi tra theo id trong danh sách hãng; không có thì hiện id.
    private func coCarrierName(_ s: CompanySession) -> String {
        if let n = s.carrier?.name, !n.isEmpty { return n }
        if let n = coCarriers[s.carrierId] { return n }
        return tr("hãng {0}", s.carrierId)
    }

    /// Mỗi thông tin một dòng, có icon: cửa · người giao · xe (biển số, loại xe) · giờ xe đến · trạm · người mở phiên.
    @ViewBuilder
    private func coInfoRows(_ s: CompanySession) -> some View {
        let vehicle = [s.licensePlate, s.vehicleType].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        let name: String? = s.user.map { u in (u.fullName ?? "").isEmpty ? u.username : (u.fullName ?? u.username) }
        VStack(alignment: .leading, spacing: 3) {
            if let gate = s.dockGate, !gate.isEmpty { infoRow("door.left.hand.closed", gate) }
            if let driver = s.driverName, !driver.isEmpty { infoRow("steeringwheel", driver) }
            if !vehicle.isEmpty { infoRow("box.truck", vehicle) }
            if let t = coTime(s.vehicleArrivedAt) { infoRow("clock", t) }
            if let station = s.station?.code, !station.isEmpty { infoRow("building.2", station) }
            if let name, !name.isEmpty { infoRow("person.crop.circle", tr("mở bởi ") + name) }
        }
    }

    private func infoRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon).frame(width: 18)
            Text(text)
        }
        .font(.subheadline).foregroundStyle(.secondary)
    }

    /// Xanh khi đã đủ kiện (đã quét ≥ hãng khai), vàng khi còn thiếu.
    private func coCountColor(_ s: CompanySession) -> Color {
        guard let reported = s.carrierReportedCount else { return .primary }
        return (s.actualScannedCount ?? 0) >= reported ? Color.okGreen : Color.yellow
    }

    // MARK: Bộ lọc (giống web)

    private var coGates: [String] {
        var set = knownGates
        if !fGate.isEmpty { set.insert(fGate) }
        return set.sorted()
    }

    /// Cả 4 bộ lọc (hãng, trạng thái, cửa, giờ xe đến) đều gọi API; danh sách hiện đúng như máy chủ trả về.
    private var shown: [CompanySession] { coSessions }

    private var filterActive: Bool { fCarrier != 0 || !fStatus.isEmpty || !fGate.isEmpty || fFrom != nil || fTo != nil }

    private func chip(_ title: String, _ value: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.bold()).foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(active ? Color.accent.opacity(0.25) : Color(.secondarySystemFill), in: Capsule())
        .foregroundStyle(.primary)
    }

    private var dateChipValue: String {
        let f = DateFormatter(); f.dateFormat = "dd/MM"
        switch (fFrom, fTo) {
        case (nil, nil): return tr("Tất cả")
        case (let a?, nil): return f.string(from: a) + " →"
        case (nil, let b?): return "→ " + f.string(from: b)
        case (let a?, let b?): return f.string(from: a) + " → " + f.string(from: b)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker(tr("Hãng"), selection: $fCarrier) {
                        Text(tr("Tất cả")).tag(0)
                        ForEach(coCarriers.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }, id: \.key) { Text($0.value).tag($0.key) }
                    }
                } label: { chip(tr("Hãng"), fCarrier == 0 ? tr("Tất cả") : (coCarriers[fCarrier] ?? "#\(fCarrier)"), active: fCarrier != 0) }

                Menu {
                    Picker(tr("Trạng thái"), selection: $fStatus) {
                        Text(tr("Tất cả")).tag("")
                        Text(tr("Đang mở")).tag("OPEN")
                        Text(tr("Đã đóng")).tag("CLOSED")
                    }
                } label: { chip(tr("Trạng thái"), fStatus.isEmpty ? tr("Tất cả") : (fStatus == "OPEN" ? tr("Đang mở") : tr("Đã đóng")), active: !fStatus.isEmpty) }

                Menu {
                    Picker(tr("Cửa"), selection: $fGate) {
                        Text(tr("Tất cả")).tag("")
                        ForEach(coGates, id: \.self) { Text($0).tag($0) }
                    }
                } label: { chip(tr("Cửa"), fGate.isEmpty ? tr("Tất cả") : fGate, active: !fGate.isEmpty) }

                Button { showDates = true } label: { chip(tr("Giờ xe đến"), dateChipValue, active: fFrom != nil || fTo != nil) }

                if filterActive {
                    Button(role: .destructive) {
                        fCarrier = 0; fStatus = ""; fGate = ""; fFrom = nil; fTo = nil
                    } label: { Text(tr("Xoá lọc")).font(.subheadline.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 8) }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// "đã quét / hãng khai" giống web (vd 6 / 20).
    private func coCount(_ s: CompanySession) -> String {
        let scanned = s.actualScannedCount ?? 0
        guard let reported = s.carrierReportedCount else { return "\(scanned)" }
        return "\(scanned) / \(reported)"
    }

    private func coDate(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let withMs = ISO8601DateFormatter()
        withMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return withMs.date(from: iso) ?? plain.date(from: iso)
    }

    /// Đổi chuỗi giờ ISO của API sang giờ máy: dd/MM HH:mm.
    private func coTime(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        guard let d = coDate(iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "dd/MM HH:mm"
        return out.string(from: d)
    }

    /// GET receiving-sessions (lọc theo hãng và trạng thái đang chọn).
    private func loadCompany() async {
        guard CompanyAPI.shared.isSignedIn else { coSessions = []; coError = nil; return }
        let token = UUID()
        loadToken = token
        coLoading = true
        defer { if loadToken == token { coLoading = false } }
        do {
            if coCarriers.isEmpty, let cs = try? await CompanyAPI.shared.carriers() {
                coCarriers = Dictionary(cs.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            }
            let cal = Calendar.current
            let from = fFrom.map { cal.startOfDay(for: $0) }                                   // 00:00 ngày bắt đầu
            let to = fTo.flatMap { cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: $0))?.addingTimeInterval(-1) }   // 23:59:59 ngày kết thúc
            let list = try await CompanyAPI.shared.sessions(status: fStatus.isEmpty ? nil : fStatus,
                                                            carrierId: fCarrier == 0 ? nil : fCarrier,
                                                            dockGate: fGate.isEmpty ? nil : fGate,
                                                            arrivedFrom: from, arrivedTo: to)
            guard loadToken == token else { return }
            knownGates.formUnion(list.compactMap { $0.dockGate }.filter { !$0.isEmpty })
            coSessions = list.sorted { $0.id > $1.id }
            coError = nil
        } catch {
            guard loadToken == token else { return }
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
    @State private var live: CompanySession?       // bản mới nhất của phiên (số đã quét cập nhật khi quay lại màn này)
    @State private var items: [CompanyTracking] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var error: String?
    @State private var checkCode = ""
    @State private var copiedId: String?           // kiện vừa sao chép mã (hiện dấu ✓ trong 1,5 giây)
    @State private var checking = false
    @State private var checkFound: Bool?           // nil = chưa kiểm tra; true = đã có trong danh sách đã quét
    @State private var checkError: String?
    @State private var confirmClose = false        // hỏi xác nhận trước khi đóng phiên trên công ty
    @State private var closing = false
    @State private var closedNow = false           // vừa đóng xong trong lần xem này
    @State private var closeError: String?
    @Environment(\.dismiss) private var dismiss
    private let pageSize = 30

    private var current: CompanySession { live ?? session }

    /// Chép mã tracking của kiện vào bộ nhớ tạm; hiện ✓ xanh 1,5 giây.
    private func copyTracking(_ t: CompanyTracking) {
        UIPasteboard.general.string = t.trackingNumber
        Haptics.success()
        copiedId = t.id
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedId == t.id { copiedId = nil }
        }
    }

    /// Số thứ tự của kiện theo lúc quét: máy chủ trả kiện quét đầu tiên ở trên cùng (sort=checkedInAt, order=asc), nên số = vị trí dòng.
    private func rowNumber(_ index: Int) -> Int { index + 1 }

    /// Xanh khi đã đủ kiện (đã quét ≥ hãng khai), vàng khi còn thiếu.
    private var countColor: Color {
        guard let reported = current.carrierReportedCount else { return .primary }
        return (current.actualScannedCount ?? 0) >= reported ? Color.okGreen : Color.yellow
    }

    var body: some View {
        List {
            // Đã quét / hãng khai: to, canh giữa, không ghi chú thêm
            Section {
                VStack(spacing: 10) {
                    CarrierLogo(name: carrierName, code: session.carrier?.code, height: 34)
                    Text("\(current.actualScannedCount ?? 0) / " + (current.carrierReportedCount.map(String.init) ?? "—"))
                        .font(.system(size: 52, weight: .heavy).monospacedDigit())
                        .foregroundStyle(countColor)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }

            // Một ô quét/gõ mã: có trong danh sách đã quét thì báo
            Section {
                TextField(tr("Gõ hoặc dán mã tracking"), text: $checkCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .submitLabel(.search)
                    .onSubmit { Task { await runCheck() } }
                    .onChange(of: checkCode) { _ in checkFound = nil; checkError = nil }
                if checking {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let checkError {
                    Label(checkError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.accent)
                } else if let checkFound {
                    if checkFound {
                        Label(tr("Đã có trong danh sách đã quét"), systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(Color.okGreen)
                    } else {
                        Label(tr("Chưa có trong danh sách đã quét"), systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if current.status == "OPEN" && !closedNow {
                Section {
                    NavigationLink {
                        AutoScanView(session: ReceivingSession(id: session.id, carrierName: carrierName, driverName: session.driverName,
                                                               licensePlate: session.licensePlate, gateCode: session.dockGate, status: "OPEN",
                                                               totalExpectedPackages: session.carrierReportedCount ?? 0,
                                                               scannedCount: session.actualScannedCount ?? 0),
                                     company: CompanyScanTarget(sessionId: session.id, carrierId: session.carrierId))
                    } label: {
                        Label(tr("Tiếp tục quét"), systemImage: "viewfinder").foregroundStyle(Color.accent)
                    }
                }
            }

            Section {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.accent)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, t in
                    NavigationLink { CompanyTrackingDetailView(tracking: t) } label: {
                        HStack(alignment: .center, spacing: 12) {
                            // Số thứ tự theo lúc quét: 1 = kiện quét đầu tiên (dòng trên cùng); nằm giữa ô theo chiều dọc
                            Text("\(rowNumber(index))")
                                .font(.title3.weight(.heavy).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .frame(minWidth: 34, alignment: .center)
                        VStack(alignment: .leading, spacing: 4) {
                            // Mã dài: ăn hết chiều ngang dòng riêng, tự thu nhỏ chữ cho vừa 1 dòng (không cắt "…", không rớt dòng)
                            HStack(spacing: 4) {
                                Text(t.trackingNumber).font(.subheadline.monospaced().bold())
                                    .lineLimit(1).minimumScaleFactor(0.5).allowsTightening(true)
                                // Nút sao chép nhỏ kế bên mã (bấm nút không mở chi tiết kiện); giữ lâu lên dòng cũng ra menu "Sao chép mã"
                                Button { copyTracking(t) } label: {
                                    Image(systemName: copiedId == t.id ? "checkmark.circle.fill" : "doc.on.doc")
                                        .font(.footnote)
                                        .foregroundStyle(copiedId == t.id ? Color.okGreen : Color.accent)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(tr("Sao chép mã"))
                            }
                            // Mỗi thông tin một dòng: khách/kệ (nếu có) · trạng thái + giờ nhập · nhãn (nếu có)
                            let who = [t.customerCode.map { tr("khách {0}", $0) }, t.binLocation.map { tr("kệ {0}", $0) }]
                                .compactMap { $0 }.joined(separator: " · ")
                            if !who.isEmpty {
                                Text(who).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Text([coStatusText(t.status), coFormatTime(t.checkedInAt)].joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            // Nhãn (nếu có) ở dòng cuối
                            if t.isUnknown || t.condition == "DAMAGED" {
                                HStack(spacing: 6) {
                                    if t.isUnknown {
                                        Text(tr("Kiện không xác định")).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.2), in: Capsule())
                                    }
                                    if t.condition == "DAMAGED" {
                                        Text(tr("HƯ HỎNG")).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.dupRed.opacity(0.25), in: Capsule())
                                    }
                                }
                            }
                        }
                        }
                    }
                    .contextMenu { Button { copyTracking(t) } label: { Label(tr("Sao chép mã"), systemImage: "doc.on.doc") } }
                    .onAppear { if t.id == items.last?.id { Task { await loadMore() } } }
                }
                if loading { HStack { Spacer(); ProgressView(); Spacer() } }
            }

            // Kết thúc phiên: nằm cuối màn hình, luôn hỏi xác nhận
            if current.status == "OPEN" && !closedNow {
                Section {
                    Button(role: .destructive) { confirmClose = true } label: {
                        HStack {
                            Spacer()
                            Label(tr("Kết thúc phiên"), systemImage: "checkmark.seal")
                            if closing { ProgressView().padding(.leading, 6) }
                            Spacer()
                        }
                    }
                    .disabled(closing)
                }
            }
        }
        .navigationTitle(tr("Phiên #{0}", session.id))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Tiêu đề to, dễ nhìn (mặc định của hệ thống khá nhỏ)
            ToolbarItem(placement: .principal) {
                Text(tr("Phiên #{0}", session.id))
                    .font(.system(size: 26, weight: .heavy))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .onAppear { Task { await refreshAll() } }      // quay lại từ màn quét thì số đã quét và danh sách kiện được tải lại
        .refreshable { await refreshAll() }
        .alert(tr("Kết thúc phiên?"), isPresented: $confirmClose) {
            Button(tr("Huỷ"), role: .cancel) {}
            Button(tr("Kết thúc phiên"), role: .destructive) { Task { await closeSession() } }
        } message: { Text(tr("Phiên #{0} sẽ được đóng trên công ty, không quét thêm vào phiên này được. Đã quét {1} kiện.", session.id, current.actualScannedCount ?? items.count)) }
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
            Haptics.success()
            dismiss()
        } catch {
            closeError = error.localizedDescription
        }
    }

    /// Mã đã nằm trong danh sách đã quét chưa: tìm trong các kiện đã tải của phiên, nếu chưa thấy thì hỏi công ty (DUPLICATE = đã quét rồi).
    private func runCheck() async {
        let code = TrackingCutter.normalize(checkCode)
        guard !code.isEmpty else { return }
        checking = true; checkError = nil
        defer { checking = false }
        let cands = TrackingCutter.candidates(code).list
        let set = Set(cands)
        if items.contains(where: { t in
            set.contains(TrackingCutter.normalize(t.trackingNumber)) ||
            t.additionalTrackingNumbers.contains { set.contains(TrackingCutter.normalize($0)) }
        }) { checkFound = true; Haptics.success(); return }
        do {
            for c in cands.prefix(4) {
                let r = try await CompanyAPI.shared.checkTracking(code: c)
                if r.status == "DUPLICATE" { checkFound = true; Haptics.success(); return }
            }
            checkFound = false
        } catch {
            checkFound = nil; checkError = error.localizedDescription
        }
    }

    private func refreshAll() async {
        if let fresh = try? await CompanyAPI.shared.session(id: session.id) { live = fresh }
        await reload()
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
            }
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
        } message: { Text(tr("Phiên mới sẽ được tạo trên hệ thống công ty.")) }
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


// MARK: - Bộ lọc "Giờ xe đến" (khoảng ngày)
struct DateRangeSheet: View {
    @Binding var from: Date?
    @Binding var to: Date?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(tr("Từ ngày"), isOn: Binding(get: { from != nil }, set: { from = $0 ? (from ?? Date()) : nil }))
                    if let f = from {
                        DatePicker(tr("Ngày bắt đầu"), selection: Binding(get: { f }, set: { from = $0 }), displayedComponents: .date)
                    }
                    Toggle(tr("Đến ngày"), isOn: Binding(get: { to != nil }, set: { to = $0 ? (to ?? Date()) : nil }))
                    if let t = to {
                        DatePicker(tr("Ngày kết thúc"), selection: Binding(get: { t }, set: { to = $0 }), displayedComponents: .date)
                    }
                }
                Section {
                    Button(tr("Xoá lọc"), role: .destructive) { from = nil; to = nil }
                }
            }
            .navigationTitle(tr("Giờ xe đến"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Xong")) { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

/// Logo hãng giao hàng (ảnh vector trong Assets, không có nền).
/// Hãng chưa có logo (vd. "Other") thì hiện tên chữ như cũ.
struct CarrierLogo: View {
    let name: String
    var code: String? = nil
    var height: CGFloat = 26

    /// Tên ảnh trong Assets theo tên/mã hãng (FEDEX EXPRESS, FEDEX GROUND, FedEx → cùng logo FedEx).
    static func asset(name: String, code: String?) -> String? {
        for text in [name, code ?? ""] {
            let tokens = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            let joined = tokens.joined()
            if joined.contains("fedex") { return "logo_fedex" }
            if joined.contains("dhl") { return "logo_dhl" }
            if joined.contains("ontrac") { return "logo_ontrac" }
            if joined.contains("amazon") { return "logo_amazon" }
            if tokens.contains("usps") { return "logo_usps" }
            if tokens.contains("ups") { return "logo_ups" }
        }
        return nil
    }

    var body: some View {
        if let asset = Self.asset(name: name, code: code) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: height * 3.6, maxHeight: height)
                .accessibilityLabel(name)
        } else {
            Text(name).font(.headline).foregroundStyle(Color.accent)
        }
    }
}
