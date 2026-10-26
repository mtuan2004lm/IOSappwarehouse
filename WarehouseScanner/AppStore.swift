import Foundation
import SwiftUI

/// Trạng thái dùng chung: địa chỉ server, bộ quy tắc mã kho (lưu cache để dùng khi mất mạng).
@MainActor
final class AppStore: ObservableObject {
    @Published var serverURL: String { didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") } }
    @Published private(set) var rules: [WarehouseRule] = []
    @Published private(set) var matcher = RuleMatcher(rules: [])
    @Published var connectionMessage: String?
    @Published var isConnected = false

    /// Địa chỉ dùng sẵn khi app mới cài (chưa có gì được lưu). Dùng tên máy Mac (.local) nên không đổi khi IP thay đổi.
    /// Muốn đổi: sửa dòng này rồi Run lại, hoặc nhập trong ⚙️ (địa chỉ nhập tay được ưu tiên và được nhớ).
    /// Dấu bản build, hiện trong ⚙️ để biết iPhone đang chạy bản nào (đổi mỗi lần sửa logic quét).
    static let buildTag = "2026-10-19 · giao diện quét mới + tạo/kết thúc phiên + VI/EN"

    static let defaultServerURL = "http://MacBook-Air-cua-Minh.local:3000"

    var api: APIClient { APIClient(baseURL: serverURL) }
    var hasServer: Bool { !serverURL.trimmingCharacters(in: .whitespaces).isEmpty }

    init() {
        let saved = UserDefaults.standard.string(forKey: "serverURL")?.trimmingCharacters(in: .whitespaces) ?? ""
        serverURL = saved.isEmpty ? AppStore.defaultServerURL : saved
        // Quy tắc mã kho cài sẵn trong app (từ 26/10/2026), không còn tải từ server cũ.
        apply(WarehouseRule.builtIn)
    }

    private func apply(_ r: [WarehouseRule]) {
        rules = r
        matcher = RuleMatcher(rules: r)
    }

    /// Kiểm tra kết nối server cũ (chỉ dùng cho phiên server riêng). Quy tắc mã kho đã cài sẵn trong app nên không tải nữa.
    func refresh() async {
        guard hasServer else { connectionMessage = tr("Quy tắc mã kho cài sẵn trong app: {0} quy tắc", rules.count); isConnected = false; return }
        do {
            _ = try await api.health()
            isConnected = true
            connectionMessage = tr("Đã kết nối server cũ · quy tắc mã kho cài sẵn trong app ({0} quy tắc)", rules.count)
        } catch {
            isConnected = false
            connectionMessage = tr("Không kết nối server cũ (không ảnh hưởng quét công ty) · quy tắc mã kho cài sẵn trong app ({0} quy tắc)", rules.count)
        }
    }
}

extension WarehouseRule {
    /// Quy tắc mã kho cài sẵn (chép từ bảng warehouse_rules mặc định của server, đã gồm bản sửa FADO.VN cho "FD VAT HUE").
    /// Muốn đổi quy tắc: sửa danh sách này rồi build lại app. Thứ tự = thứ tự ưu tiên (rule đầu tiên khớp thắng).
    static let builtIn: [WarehouseRule] = [
        WarehouseRule(id: 1, customerGroup: "Giaonhan247", patternRegex: "^(SGKYDUYEN_|HNKYDUYEN_|SGVO_|HNVO_)",
                      businessType: "KHONG_KINH_DOANH", requiresImportCheck: false, isActive: true),
        WarehouseRule(id: 2, customerGroup: "FADO 168", patternRegex: "^(CHHEN_|SG HUE_DOFA168|SG FRAGILE_DOFA168)",
                      businessType: "KHONG_KINH_DOANH", requiresImportCheck: false, isActive: true),
        WarehouseRule(id: 3, customerGroup: "MICAFI", patternRegex: "(MCF$|MCF\\s)",
                      businessType: "KHONG_KINH_DOANH", requiresImportCheck: false, isActive: true),
        WarehouseRule(id: 4, customerGroup: "FADO.VN", patternRegex: "^(FD ?VAT ?HUE|SG ?HUE DOFA|HN ?BANGTY DOFA|SG ?FRAGILE DOFA|HN ?FRAGILE DOFA)",
                      businessType: "KINH_DOANH", requiresImportCheck: true, isActive: true),
    ]
}
