import Foundation
import SwiftUI

/// Trạng thái dùng chung: bộ quy tắc mã kho cài sẵn trong app (không cần mạng).
@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var rules: [WarehouseRule] = []
    @Published private(set) var matcher = RuleMatcher(rules: [])

    init() {
        // Quy tắc mã kho cài sẵn trong app (từ 26/10/2026), không tải từ server nào.
        let r = WarehouseRule.builtIn
        rules = r
        matcher = RuleMatcher(rules: r)
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
