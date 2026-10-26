import SwiftUI

/// Chi tiết một phiên: số đã quét / dự kiến, danh sách đơn đã quét (tự cập nhật mỗi 1 giây như web) và nút Bắt đầu quét.
struct SessionDetailView: View {
    @EnvironmentObject var lang: LangStore   // đổi ngôn ngữ thì làm mới màn hình
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var session: ReceivingSession
    @State private var items: [SessionItem] = []
    @State private var offline = false
    @State private var showScan = false
    @State private var confirmClose = false
    @State private var actionError: String?

    init(session: ReceivingSession) { _session = State(initialValue: session) }

    private var isOpen: Bool { session.status == "OPEN" }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(session.carrierName).font(.headline).foregroundStyle(Color.accent)
                        Text([session.gateCode, session.driverName, session.licensePlate]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if !isOpen { Text(tr("Phiên đã kết thúc")).font(.footnote.bold()).foregroundStyle(Color.dupRed) }
                    if offline { Label(tr("Mất kết nối, đang thử lại…"), systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(Color.accent) }
                    if let e = actionError { Text(e).font(.footnote).foregroundStyle(Color.accent) }
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))

                HStack(spacing: 10) {
                    countBox(tr("ĐÃ QUÉT"), session.scannedCount, .okGreen)
                    countBox(tr("DỰ KIẾN"), session.totalExpectedPackages, .white)
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }

            Section(tr("Đơn đã quét ({0})", items.count)) {
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "shippingbox").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text(isOpen ? tr("Chưa có đơn nào. Bấm \"Bắt đầu quét\" để quét đơn đầu tiên.") : tr("Phiên không có đơn nào."))
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                }
                ForEach(items) { it in itemRow(it) }
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isOpen {
                    Button(tr("Kết thúc phiên"), role: .destructive) { confirmClose = true }.tint(Color.dupRed)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isOpen {
                Button { showScan = true } label: {
                    Label(items.isEmpty ? tr("Bắt đầu quét") : tr("Tiếp tục quét"), systemImage: "viewfinder")
                        .font(.title3.weight(.heavy)).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent).tint(.accent)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
                .background(.ultraThinMaterial)
            }
        }
        .navigationDestination(isPresented: $showScan) { AutoScanView(session: session) }
        .alert(tr("Kết thúc phiên?"), isPresented: $confirmClose) {
            Button(tr("Huỷ"), role: .cancel) {}
            Button(tr("Kết thúc"), role: .destructive) { Task { await close() } }
        } message: { Text(tr("Sau khi kết thúc sẽ không quét thêm được.")) }
        // Tự hỏi server mỗi 1 giây (như web); dừng khi rời màn hình hoặc đang ở màn quét.
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func countBox(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.caption2.bold()).tracking(1.2).foregroundStyle(.white.opacity(0.7))
            Text("\(value)").font(.system(size: 34, weight: .heavy, design: .monospaced)).foregroundStyle(color)
                .minimumScaleFactor(0.5).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Color.navy, in: RoundedRectangle(cornerRadius: 14))
    }

    private func itemRow(_ it: SessionItem) -> some View {
        let badge = badgeFor(it)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(it.barcode).font(.system(.subheadline, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
                Text(subtitle(it)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(badge.text).font(.caption2.weight(.heavy)).foregroundStyle(badge.color)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(badge.color.opacity(0.2), in: Capsule())
        }
    }

    private func subtitle(_ it: SessionItem) -> String {
        let parts = [it.customerGroup, it.detectedWarehouseCode].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? tr("Không xác định") : parts.joined(separator: " · ")
    }

    private func badgeFor(_ it: SessionItem) -> (text: String, color: Color) {
        if it.isNoName == true { return ("NO NAME", Color.purple) }
        switch it.exceptionStatus {
        case "DAMAGED": return (tr("HỎNG"), Color.dupRed)
        case "HOLDING": return (tr("GIỮ"), Color.accent)
        case "BLOCKED": return ("BLOCK", Color.dupRed)
        case "UNKNOWN": return (tr("KHÔNG XÁC ĐỊNH"), Color.unknownGray)
        default: return ("SUCCESS", Color.okGreen)
        }
    }

    private func refresh() async {
        do {
            let d = try await store.api.sessionDetail(id: session.id)
            if d.session != session { session = d.session }
            if d.items != items { items = d.items }
            offline = false
        } catch {
            offline = true          // giữ nguyên danh sách đang hiện, tự thử lại ở lần sau
        }
    }

    private func close() async {
        do {
            _ = try await store.api.closeSession(id: session.id)
            Haptics.success()
            dismiss()
        } catch {
            actionError = error.localizedDescription
            Haptics.error()
        }
    }
}
