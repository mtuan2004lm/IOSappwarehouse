import Foundation

// MARK: - Mô hình dữ liệu khớp với API của web (snake_case -> camelCase tự động)

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

struct ReceivingSession: Codable, Identifiable, Hashable {
    let id: Int
    let carrierName: String
    let driverName: String?
    let licensePlate: String?
    let gateCode: String?
    let status: String                // OPEN | CLOSED
    let totalExpectedPackages: Int
    let scannedCount: Int
    var title: String { tr("Phiên #") + String(format: "%04d", id) }
}

struct ScannedItem: Codable, Identifiable, Hashable {
    let id: FlexID
    let sessionId: Int
    let barcode: String
    let detectedWarehouseCode: String?
    let customerGroup: String?
    let businessType: String?
    let exceptionStatus: String
    let isNoName: Bool?
}

/// Một dòng trong danh sách đơn của phiên (GET /receiving/sessions/:id).
struct SessionItem: Decodable, Identifiable, Hashable {
    let id: FlexID
    let barcode: String
    let detectedWarehouseCode: String?
    let customerGroup: String?
    let businessType: String?
    let exceptionStatus: String
    let isNoName: Bool?
}

struct SessionDetail: Decodable { let session: ReceivingSession; let items: [SessionItem] }

struct Pagination: Codable { let page: Int; let limit: Int; let total: Int; let totalPages: Int }
struct ListResponse<T: Decodable>: Decodable { let data: [T]; let pagination: Pagination? }
struct ObjectResponse<T: Decodable>: Decodable { let data: T }

/// Kết quả một lần quét tracking:
///  status = SUCCESS (tracking có thông tin -> ghi 1 kiện), TRACK (chưa có thông tin -> "ting", chờ mã tiếp theo), NO_NAME (quét END CODE -> kiện NO NAME)
struct ScanData: Decodable {
    let status: String?
    let item: ScannedItem?
    let seq: Int?
    let needEndCode: Bool?
    let barcode: String?
    let scannedCount: Int?
    let totalExpectedPackages: Int?
}

struct ScanFailData: Decodable { let status: String }

struct PhotoData: Decodable { let item: ScannedItem; let photoUrl: String }

// MARK: - Lỗi

struct APIError: LocalizedError {
    let status: Int          // 0 = lỗi mạng
    let code: String?
    let message: String
    var errorDescription: String? { message }
    var isDuplicate: Bool { code == "DUPLICATE_BARCODE" }
    var isNetwork: Bool { status == 0 }
    var isEndCodeRequired: Bool { code == "END_CODE_REQUIRED" }
}
