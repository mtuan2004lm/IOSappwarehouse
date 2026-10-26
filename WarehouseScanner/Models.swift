import Foundation

// MARK: - Mô hình dùng chung cho màn quét

/// id của kiện là BIGSERIAL nên server trả về chuỗi ("21"); chấp nhận cả số lẫn chuỗi.
struct FlexID: Codable, Hashable {
    let value: String
    init(_ value: String) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = String(i) }
        else { value = try c.decode(String.self) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

struct WarehouseRule: Codable, Identifiable, Hashable {
    let id: Int
    let customerGroup: String
    let patternRegex: String
    let businessType: String          // KINH_DOANH | KHONG_KINH_DOANH
    let requiresImportCheck: Bool
    let isActive: Bool
    var isBusiness: Bool { businessType == "KINH_DOANH" }
}

/// Phiên nhận hàng đang quét (dựng từ phiên công ty để màn quét dùng).
struct ReceivingSession: Hashable {
    let id: Int
    let carrierName: String
    let driverName: String?
    let licensePlate: String?
    let gateCode: String?
    let status: String                // OPEN | CLOSED
    let totalExpectedPackages: Int
    let scannedCount: Int
}

/// Kiện vừa quét xong (để gắn ảnh label / báo hư hỏng).
struct ScannedItem: Identifiable, Hashable {
    let id: FlexID
    let sessionId: Int
    let barcode: String
    let detectedWarehouseCode: String?
    let customerGroup: String?
    let businessType: String?
    let exceptionStatus: String
    let isNoName: Bool?
}
