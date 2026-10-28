import Foundation
import Security

// MARK: - API công ty (apiwh-dev)
// Đăng nhập/làm mới token, đọc phiên + kiện, tạo phiên, quét, ảnh label, báo hư hỏng.
// Token lưu trong Keychain; mật khẩu không bao giờ được lưu.

/// Lưu chuỗi nhỏ (token) vào Keychain của máy.
enum KeychainStore {
    private static let service = "com.tinashipping.warehouse.company"

    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        _ = SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        _ = SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func remove(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        _ = SecItemDelete(q as CFDictionary)
    }
}

struct CompanyError: LocalizedError {
    let status: Int
    let code: String?
    let message: String
    var errorDescription: String? {
        if status <= 0 { return message }
        let extra = code ?? ""
        return extra.isEmpty ? "\(message) (HTTP \(status))" : "\(message) (HTTP \(status), \(extra))"
    }
}

// Khung phản hồi của API công ty: { success, statusCode, message, data, meta? }
struct CompanyEnvelope<T: Decodable>: Decodable { let data: T }
struct CompanyList<T: Decodable>: Decodable { let data: [T] }
struct CompanyOK: Decodable { let success: Bool }
struct CompanyErrorBody: Decodable { let code: String?; let message: String? }
struct CompanyUserRef: Decodable { let id: String; let username: String; let fullName: String? }
struct CompanyTokens: Decodable { let accessToken: String; let refreshToken: String }
struct CompanyRef: Decodable { let id: Int; let code: String; let name: String }
struct CompanyMe: Decodable { let id: String; let username: String; let fullName: String?; let stations: [CompanyRef] }
struct CompanyCarrier: Decodable { let id: Int; let code: String; let name: String; let isActive: Bool? }
struct CompanyMapping: Decodable { let id: Int; let customerCode: String; let destinationHubId: Int? }
struct CompanySession: Decodable {
    let id: Int
    let stationId: Int
    let carrierId: Int
    let status: String
    let driverName: String?
    let dockGate: String?
    let actualScannedCount: Int?
    let carrierReportedCount: Int?
    let licensePlate: String?
    let vehicleType: String?
    let vehicleArrivedAt: String?
    let carrier: CompanyRef?
    let station: CompanyRef?
    let user: CompanyUserRef?
}

// MARK: - Kiện (trackings) của công ty — chỉ đọc
/// Giải mã "dễ tính": số/chuỗi lẫn lộn hoặc thiếu trường đều không làm hỏng cả danh sách.
extension KeyedDecodingContainer {
    func lenientString(_ k: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: k) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: k) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: k) { return String(d) }
        return nil
    }
    func lenientDouble(_ k: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: k) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: k) { return Double(s) }
        return nil
    }
}

struct CompanyOrderItem: Decodable {
    let itemId: String?
    let clientOrderId: String?
    let itemName: String?
    let quantity: Double?
    let actualQuantity: Double?
    let damagedQuantity: Double?
    let normalQuantity: Double?
    enum CodingKeys: String, CodingKey { case itemId, clientOrderId, itemName, quantity, actualQuantity, damagedQuantity, normalQuantity }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemId = c.lenientString(.itemId); clientOrderId = c.lenientString(.clientOrderId); itemName = c.lenientString(.itemName)
        quantity = c.lenientDouble(.quantity); actualQuantity = c.lenientDouble(.actualQuantity)
        damagedQuantity = c.lenientDouble(.damagedQuantity); normalQuantity = c.lenientDouble(.normalQuantity)
    }
}

struct CompanyHoldCase: Decodable {
    let reasonName: String?
    let resolvedAt: String?
    let resolution: String?
    enum CodingKeys: String, CodingKey { case holdCase, resolvedAt, resolution }
    enum CaseKeys: String, CodingKey { case caseId, reason }
    enum ReasonKeys: String, CodingKey { case code, name }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        resolvedAt = c.lenientString(.resolvedAt); resolution = c.lenientString(.resolution)
        var name: String?
        if let hc = try? c.nestedContainer(keyedBy: CaseKeys.self, forKey: .holdCase),
           let rc = try? hc.nestedContainer(keyedBy: ReasonKeys.self, forKey: .reason) {
            name = rc.lenientString(.name) ?? rc.lenientString(.code)
        }
        reasonName = name
    }
}

struct CompanyTracking: Decodable, Identifiable {
    let id: String
    let trackingNumber: String
    let additionalTrackingNumbers: [String]
    let carrierId: Int?
    let customerCode: String?
    let status: String?
    let condition: String?
    let matchStatus: String?
    let binLocation: String?
    let receivingSessionId: Int?
    let orderItemCount: Double?
    let totalQuantity: Double?
    let totalActualQuantity: Double?
    let totalDamagedQuantity: Double?
    let checkedInAt: String?
    let labelPhotoCount: Int
    let labelPhotoURLs: [String]      // link ảnh tem (https://…/uploads/trackings/<id>/label-….jpg)
    let orderItems: [CompanyOrderItem]
    let holdCases: [CompanyHoldCase]
    enum CodingKeys: String, CodingKey {
        case id, trackingNumber, additionalTrackingNumbers, carrierId, customerCode, status, condition, matchStatus, binLocation
        case receivingSessionId, orderItemCount, totalQuantity, totalActualQuantity, totalDamagedQuantity, checkedInAt
        case labelPhotos, labelPhotoUrls, orderItems, holdCaseItems
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? UUID().uuidString
        trackingNumber = c.lenientString(.trackingNumber) ?? "?"
        additionalTrackingNumbers = (try? c.decodeIfPresent([String].self, forKey: .additionalTrackingNumbers)) ?? []
        carrierId = (c.lenientDouble(.carrierId)).map { Int($0) }
        customerCode = c.lenientString(.customerCode)
        status = c.lenientString(.status); condition = c.lenientString(.condition); matchStatus = c.lenientString(.matchStatus)
        binLocation = c.lenientString(.binLocation)
        receivingSessionId = (c.lenientDouble(.receivingSessionId)).map { Int($0) }
        orderItemCount = c.lenientDouble(.orderItemCount); totalQuantity = c.lenientDouble(.totalQuantity)
        totalActualQuantity = c.lenientDouble(.totalActualQuantity); totalDamagedQuantity = c.lenientDouble(.totalDamagedQuantity)
        checkedInAt = c.lenientString(.checkedInAt)
        let urls = (try? c.decodeIfPresent([String].self, forKey: .labelPhotoUrls)) ?? []
        let photos = (try? c.decodeIfPresent([CompanyPhotoRef].self, forKey: .labelPhotos)) ?? []
        labelPhotoURLs = urls.isEmpty ? photos.compactMap { $0.url } : urls
        labelPhotoCount = max(urls.count, photos.count)
        orderItems = (try? c.decodeIfPresent([CompanyOrderItem].self, forKey: .orderItems)) ?? []
        holdCases = (try? c.decodeIfPresent([CompanyHoldCase].self, forKey: .holdCaseItems)) ?? []
    }
}

extension CompanyTracking {
    /// "Kiện không xác định" theo cách web công ty tính: `matchStatus` NO_NAME VÀ chưa có dòng hàng khai báo.
    /// (Kiện đã có `orderItems` vẫn có thể mang `matchStatus: NO_NAME` nhưng web coi là đã khớp danh sách.)
    var hasOrderLines: Bool { !orderItems.isEmpty || (orderItemCount ?? 0) > 0 }   // `orderItemCount` luôn có, `orderItems` chỉ có khi gọi kèm include
    var isUnknown: Bool { matchStatus == "NO_NAME" && !hasOrderLines }
}

/// Một ảnh trong `labelPhotos` của công ty: { id, url, originalFilename, mimeType, sizeBytes, createdAt }.
struct CompanyPhotoRef: Decodable { let url: String? }


/// Giá trị JSON bất kỳ, dùng để hiện nguyên văn phản hồi của lệnh kiểm tra (chưa biết hết cấu trúc).
enum CompanyJSON: Decodable {
    case null, bool(Bool), number(Double), string(String), array([CompanyJSON]), object([String: CompanyJSON])
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let t = try? c.decode(String.self) { self = .string(t) }
        else if let a = try? c.decode([CompanyJSON].self) { self = .array(a) }
        else if let o = try? c.decode([String: CompanyJSON].self) { self = .object(o) }
        else { self = .null }
    }
    var stringValue: String? { if case .string(let t) = self { return t }; return nil }
    var intValue: Int? {
        if case .number(let n) = self { return Int(n) }
        if case .string(let t) = self { return Int(t) }
        return nil
    }
    subscript(key: String) -> CompanyJSON? { if case .object(let o) = self { return o[key] }; return nil }
    /// Dạng chữ nhiều dòng, dễ đọc.
    func pretty(_ indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .string(let t): return t
        case .array(let a):
            if a.isEmpty { return "[]" }
            return a.map { "\n" + pad + "- " + $0.pretty(indent + 1) }.joined()
        case .object(let o):
            if o.isEmpty { return "{}" }
            return o.keys.sorted().map { "\n" + pad + $0 + ": " + (o[$0]?.pretty(indent + 1) ?? "") }.joined()
        }
    }
}

/// Cắt chuỗi mã vạch thành mã tracking (bản chép của server/utils/trackingFormats.js, bộ định dạng mặc định trong schema.sql).
enum TrackingCutter {
    struct Format { let detect: String; let mode: String; let param: String }
    static let formats: [Format] = [
        Format(detect: "^420\\d{5}\\d{20,}$", mode: "DROP_FIRST", param: "8"),      // USPS: 420 + ZIP5 + tracking
        Format(detect: "^420\\d{9}\\d{20,}$", mode: "DROP_FIRST", param: "12"),     // USPS: 420 + ZIP9 + tracking
        Format(detect: "^9\\d{19,33}$", mode: "FULL", param: ""),                      // USPS: 20–34 số bắt đầu bằng 9
        Format(detect: "^[A-Z]{2}\\d{9}US$", mode: "FULL", param: ""),                // USPS quốc tế
        Format(detect: "1Z[0-9A-Z]{16}", mode: "REGEX", param: "1Z[0-9A-Z]{16}"),      // UPS (kể cả trong chuỗi dài)
        Format(detect: "^\\d{30,34}$", mode: "LAST", param: "12"),                     // FedEx Express: 12 số cuối
        Format(detect: "^96\\d{20}$", mode: "LAST", param: "15"),                      // FedEx Ground: 15 số cuối
        Format(detect: "^92\\d{20}$", mode: "LAST", param: "20"),                      // FedEx SmartPost: 20 số cuối
        Format(detect: "^(\\d{12}|\\d{15})$", mode: "FULL", param: ""),               // FedEx: 12 hoặc 15 số
        Format(detect: "^\\d{10}$", mode: "FULL", param: ""),                          // DHL Express
        Format(detect: "^(JD|JJD|JVGL|GM)\\d{16,20}$", mode: "FULL", param: ""),       // DHL eCommerce
        Format(detect: "TB[ACM]\\d{12}", mode: "REGEX", param: "TB[ACM]\\d{12}"),    // Amazon Logistics
    ]

    /// Bỏ ký tự điều khiển + khoảng trắng, viết hoa.
    static func normalize(_ s: String) -> String {
        String(s.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 && !CharacterSet.whitespacesAndNewlines.contains($0) }).uppercased()
    }

    private static func has(_ pattern: String, _ s: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }

    private static func apply(_ f: Format, _ code: String) -> String? {
        guard has(f.detect, code) else { return nil }
        let n = Int(f.param) ?? 0
        switch f.mode {
        case "LAST": return n > 0 && code.count >= n ? String(code.suffix(n)) : nil
        case "DROP_FIRST": return n > 0 && code.count > n ? String(code.dropFirst(n)) : nil
        case "REGEX": return code.range(of: f.param, options: .regularExpression).map { String(code[$0]) }
        default: return code
        }
    }

    /// Ba nhóm số của ZIP+4 (nếu khớp mẫu), dùng cho mã 420 + ZIP9 và ZIP9.
    private static func groups(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1 else { return nil }
        return (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: s).map { String(s[$0]) } }
    }

    /// `list`: các mã ứng viên để hỏi công ty (mã gốc trước). `primary`: mã tracking đã cắt, dùng khi ghi kiện.
    static func candidates(_ barcode: String) -> (list: [String], primary: String) {
        let code = normalize(barcode)
        var list = [code]
        var derived: [String] = []
        for f in formats {
            guard let v = apply(f, code), v != code, !list.contains(v) else { continue }
            list.append(v); derived.append(v)
        }
        for v in list {
            if let g = groups("^420(\\d{5})(\\d{4})$", v), g.count == 2 { let x = g[0] + "-" + g[1]; if !list.contains(x) { list.append(x) } }
            if let g = groups("^(\\d{5})(\\d{4})$", v), g.count == 2 { let x = g[0] + "-" + g[1]; if !list.contains(x) { list.append(x) } }
            if v.contains("-") { let x = v.replacingOccurrences(of: "-", with: ""); if !list.contains(x) { list.append(x) } }
        }
        return (list, derived.first ?? code)
    }
}

/// Một phần của yêu cầu multipart/form-data.
struct CompanyPart { let name: String; let filename: String?; let mime: String?; let data: Data }

/// Loại hư hỏng của công ty (code dùng khi gửi báo cáo, name để hiển thị).
struct CompanyDamageType: Decodable, Identifiable {
    let code: String
    let name: String
    var id: String { code }
    enum CodingKeys: String, CodingKey { case code, name }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = c.lenientString(.code) ?? "?"
        name = c.lenientString(.name) ?? code
    }
}

/// Phiên công ty mà màn quét sẽ ghi vào.
struct CompanyScanTarget: Hashable { let sessionId: Int; let carrierId: Int }

/// Một nơi duy nhất nói chuyện với API công ty. `actor` để làm mới token không bị chạy chồng nhau.
actor CompanyAPI {
    static let shared = CompanyAPI()
    static let defaultBase = "https://apiwh-dev.tinashipping.com/api"
    static let userKey = "company.username"          // chỉ nhớ tên đăng nhập, KHÔNG nhớ mật khẩu

    private var baseURL: String { Self.defaultBase }

    nonisolated var isSignedIn: Bool { KeychainStore.get("accessToken") != nil }

    // MARK: Đăng nhập

    func login(username: String, password: String) async throws -> CompanyMe {
        let r = try await request(CompanyEnvelope<CompanyTokens>.self, "POST", "/auth/login",
                                  json: ["username": username, "password": password], auth: false)
        save(r.data)
        UserDefaults.standard.set(username, forKey: Self.userKey)
        return try await me()
    }

    func logout() async {
        if let rt = KeychainStore.get("refreshToken") {
            _ = try? await request(CompanyEnvelope<CompanyOK>.self, "POST", "/auth/logout", json: ["refreshToken": rt], auth: false)
        }
        KeychainStore.remove("accessToken")
        KeychainStore.remove("refreshToken")
    }

    private func save(_ t: CompanyTokens) {
        KeychainStore.set(t.accessToken, for: "accessToken")
        KeychainStore.set(t.refreshToken, for: "refreshToken")
    }

    /// Báo cho app biết phiên đăng nhập đã hết hạn hẳn (làm mới token thất bại) để quay về màn đăng nhập.
    nonisolated static let sessionExpired = Notification.Name("company.sessionExpired")

    private var refreshTask: Task<Void, Error>?

    /// Nhiều lệnh cùng nhận 401 một lúc (vd. hỏi song song các mã ứng viên) chỉ được làm mới token MỘT lần;
    /// refreshToken dùng một lần nên lần làm mới thứ hai sẽ bị từ chối và làm mất đăng nhập.
    private func refreshOnce(usedToken: String?) async throws {
        if KeychainStore.get("accessToken") != usedToken { return }       // lệnh khác đã làm mới xong
        if let t = refreshTask { try await t.value; return }              // lệnh khác đang làm mới: chờ kết quả
        let t = Task { try await self.refresh() }
        refreshTask = t
        defer { refreshTask = nil }
        do { try await t.value }
        catch let e as CompanyError where e.status == 400 || e.status == 401 || e.status == 403 {
            KeychainStore.remove("accessToken")
            KeychainStore.remove("refreshToken")
            NotificationCenter.default.post(name: Self.sessionExpired, object: nil)
            throw CompanyError(status: 401, code: "SESSION_EXPIRED", message: tr("Hết phiên đăng nhập — vui lòng đăng nhập lại"))
        }
    }

    /// Làm mới token (refreshToken dùng một lần: mỗi lần làm mới nhận cặp token mới).
    private func refresh() async throws {
        guard let rt = KeychainStore.get("refreshToken") else {
            throw CompanyError(status: 401, code: "NO_TOKEN", message: tr("Chưa đăng nhập công ty"))
        }
        let r = try await request(CompanyEnvelope<CompanyTokens>.self, "POST", "/auth/refresh",
                                  json: ["refreshToken": rt], auth: false)
        save(r.data)
    }

    // MARK: Chỉ đọc

    func me() async throws -> CompanyMe {
        try await request(CompanyEnvelope<CompanyMe>.self, "GET", "/auth/me").data
    }

    func carriers() async throws -> [CompanyCarrier] {
        try await request(CompanyList<CompanyCarrier>.self, "GET", "/carriers", query: [URLQueryItem(name: "limit", value: "100")]).data
    }

    func customerCodeMappings() async throws -> [CompanyMapping] {
        try await request(CompanyList<CompanyMapping>.self, "GET", "/customer-code-mappings", query: [URLQueryItem(name: "limit", value: "100")]).data
    }

    /// Một phiên theo id (kèm `actualScannedCount` tính sẵn).
    func session(id: Int) async throws -> CompanySession {
        try await request(CompanyEnvelope<CompanySession>.self, "GET", "/receiving-sessions/\(id)").data
    }

    /// Danh sách phiên, lọc ở máy chủ giống web: trạng thái (OPEN | CLOSED), hãng, cửa (`dockGate`, khớp đúng),
    /// giờ xe đến (`openedFrom`/`openedTo` — Swagger: lọc theo `vehicleArrivedAt`). nil/rỗng = không lọc.
    func sessions(status: String?, carrierId: Int?, dockGate: String? = nil, arrivedFrom: Date? = nil, arrivedTo: Date? = nil) async throws -> [CompanySession] {
        var q = [URLQueryItem(name: "limit", value: "50")]
        if let status, !status.isEmpty { q.append(URLQueryItem(name: "status", value: status)) }
        if let carrierId, carrierId > 0 { q.append(URLQueryItem(name: "carrierId", value: String(carrierId))) }
        if let dockGate, !dockGate.isEmpty { q.append(URLQueryItem(name: "dockGate", value: dockGate)) }
        let iso = ISO8601DateFormatter()
        if let arrivedFrom { q.append(URLQueryItem(name: "openedFrom", value: iso.string(from: arrivedFrom))) }
        if let arrivedTo { q.append(URLQueryItem(name: "openedTo", value: iso.string(from: arrivedTo))) }
        return try await request(CompanyList<CompanySession>.self, "GET", "/receiving-sessions", query: q).data
    }

    /// Chỉ đọc: kiện của một phiên (GET /trackings?receivingSessionId=). Trả về một trang.
    func trackings(sessionId: Int, page: Int, limit: Int = 30) async throws -> [CompanyTracking] {
        let base = [URLQueryItem(name: "receivingSessionId", value: String(sessionId)),
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "limit", value: String(limit)),
                    // Kiện quét đầu tiên lên trên (Swagger: sort=checkedInAt, order=asc)
                    URLQueryItem(name: "sort", value: "checkedInAt"),
                    URLQueryItem(name: "order", value: "asc")]
        // Web công ty gửi thêm include=orderItems,holdCaseItems để nhận kèm dòng hàng; nếu máy chủ từ chối thì gọi lại như cũ.
        if let r = try? await request(CompanyList<CompanyTracking>.self, "GET", "/trackings",
                                      query: base + [URLQueryItem(name: "include", value: "orderItems,holdCaseItems")]) { return r.data }
        return try await request(CompanyList<CompanyTracking>.self, "GET", "/trackings", query: base).data
    }

    /// Chỉ đọc: chi tiết một kiện (GET /trackings/{id}).
    func tracking(id: String) async throws -> CompanyTracking {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        if let r = try? await request(CompanyEnvelope<CompanyTracking>.self, "GET", "/trackings/\(enc)",
                                      query: [URLQueryItem(name: "include", value: "orderItems,holdCaseItems")]) { return r.data }
        return try await request(CompanyEnvelope<CompanyTracking>.self, "GET", "/trackings/\(enc)").data
    }

    /// Chỉ đọc: báo cáo hư hỏng của một kiện (GET /trackings/{id}/damage-report) — đã xác minh bằng JSON thật 27/10/2026:
    /// { id, decision, reportedAt, damageTypes:[{code,name}], photos:[{url,…}], photoUrls:[…] }.
    func damageReport(trackingId: String) async throws -> CompanyDamageReport {
        let enc = trackingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trackingId
        let raw = try await request(CompanyEnvelope<CompanyJSON>.self, "GET", "/trackings/\(enc)/damage-report").data
        return CompanyDamageReport(json: raw)
    }

    /// Hỏi công ty "mã này đã có chưa" (POST /trackings/check-tracking-scan). Tên lệnh là "check" nên không tạo kiện.
    /// Trả về (trạng thái FOUND/NOT_FOUND/DUPLICATE, phần data nguyên văn để xem).
    func checkTracking(code: String) async throws -> (status: String, detail: String) {
        let r = try await request(CompanyEnvelope<CompanyJSON>.self, "POST", "/trackings/check-tracking-scan", json: ["code": code])
        return (r.data["status"]?.stringValue ?? "?", r.data.pretty().trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// GHI lên công ty: tạo phiên nhận hàng (POST /receiving-sessions). Chỉ gọi khi người dùng đã xác nhận.
    /// Không giải mã cả phiên (tránh báo lỗi sau khi đã tạo xong, dẫn tới bấm tạo lần nữa); chỉ lấy `id`.
    func createSession(stationId: Int, carrierId: Int, driverName: String, reportedCount: Int, dockGate: String) async throws -> Int {
        var body: [String: Any] = ["stationId": stationId, "carrierId": carrierId,
                                   "driverName": driverName, "carrierReportedCount": reportedCount]
        if !dockGate.isEmpty { body["dockGate"] = dockGate }
        let r = try await request(CompanyEnvelope<CompanyJSON>.self, "POST", "/receiving-sessions", json: body)
        return r.data["id"]?.intValue ?? 0
    }

    /// GHI lên công ty: đóng phiên nhận hàng (PATCH /receiving-sessions/{id}). Chỉ gọi khi người dùng đã xác nhận.
    /// Theo Swagger: `status` = CLOSED, thường kèm `vehicleDepartedAt` (giờ xe rời đi, ISO 8601 UTC dạng ...Z).
    /// Không giải mã phiên trả về (tránh báo lỗi sau khi đã đóng xong).
    func closeSession(id: Int) async throws {
        let departed = ISO8601DateFormatter().string(from: Date())      // vd. 2026-10-28T05:40:00Z
        _ = try await request(CompanyEnvelope<CompanyJSON>.self, "PATCH", "/receiving-sessions/\(id)",
                              json: ["status": "CLOSED", "vehicleDepartedAt": departed])
    }

    /// GHI lên công ty: quét một kiện (POST /trackings/scan). Gửi lại cùng mã thì công ty trả DUPLICATE (không tạo trùng).
    func scan(trackingNumber: String, additional: [String], carrierId: Int, customerCode: String, sessionId: Int) async throws -> (id: String, matchStatus: String, checkIn: String) {
        var body: [String: Any] = ["trackingNumber": trackingNumber, "carrierId": carrierId, "receivingSessionId": sessionId]
        if !additional.isEmpty { body["additionalTrackingNumbers"] = additional }
        if !customerCode.isEmpty { body["customerCode"] = customerCode }
        let r = try await request(CompanyEnvelope<CompanyJSON>.self, "POST", "/trackings/scan", json: body)
        let id = r.data["id"]?.stringValue ?? r.data["id"]?.intValue.map(String.init) ?? ""
        return (id, r.data["matchStatus"]?.stringValue ?? "?", r.data["checkInResult"]?.stringValue ?? "?")
    }

    /// GHI lên công ty: ảnh label của một kiện (POST /trackings/{id}/label-photos, multipart, trường `files`).
    func uploadLabelPhoto(trackingId: String, jpeg: Data) async throws {
        let enc = trackingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trackingId
        _ = try await request(CompanyJSON.self, "POST", "/trackings/\(enc)/label-photos",
                              multipart: [CompanyPart(name: "files", filename: "label.jpg", mime: "image/jpeg", data: jpeg)])
    }

    /// Đọc: danh sách loại hư hỏng của công ty (GET /damage-types).
    func damageTypes() async throws -> [CompanyDamageType] {
        try await request(CompanyList<CompanyDamageType>.self, "GET", "/damage-types", query: [URLQueryItem(name: "limit", value: "100")]).data
    }

    /// GHI lên công ty: báo hư hỏng của một kiện (POST /trackings/{id}/damage-report, multipart).
    /// decision: "RECEIVED" (nhận hàng) hoặc "REJECTED" (từ chối). Mỗi kiện chỉ có một báo cáo (gửi lần hai bị 409).
    func reportDamage(trackingId: String, typeCodes: [String], decision: String, photos: [Data]) async throws {
        let enc = trackingId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trackingId
        var parts = typeCodes.map { CompanyPart(name: "damageTypeCodes", filename: nil, mime: nil, data: Data($0.utf8)) }
        parts.append(CompanyPart(name: "decision", filename: nil, mime: nil, data: Data(decision.utf8)))
        for (i, d) in photos.enumerated() {
            parts.append(CompanyPart(name: "files", filename: "damage\(i + 1).jpg", mime: "image/jpeg", data: d))
        }
        _ = try await request(CompanyJSON.self, "POST", "/trackings/\(enc)/damage-report", multipart: parts)
    }

    // MARK: Gọi mạng chung

    private func request<T: Decodable>(_ type: T.Type, _ method: String, _ path: String,
                                       query: [URLQueryItem] = [], json: [String: Any]? = nil,
                                       multipart: [CompanyPart]? = nil,
                                       auth: Bool = true, retry: Bool = true) async throws -> T {
        guard var comps = URLComponents(string: baseURL + path) else {
            throw CompanyError(status: 0, code: "BAD_URL", message: tr("Địa chỉ API không hợp lệ"))
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw CompanyError(status: 0, code: "BAD_URL", message: tr("Địa chỉ API không hợp lệ")) }
        var req = URLRequest(url: url, timeoutInterval: multipart == nil ? 15 : 90)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        if let parts = multipart {
            let boundary = "Boundary-" + UUID().uuidString
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            for part in parts {
                var head = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(part.name)\""
                if let f = part.filename { head += "; filename=\"\(f)\"" }
                head += "\r\n"
                if let m = part.mime { head += "Content-Type: \(m)\r\n" }
                body.append(Data((head + "\r\n").utf8))
                body.append(part.data)
                body.append(Data("\r\n".utf8))
            }
            body.append(Data("--\(boundary)--\r\n".utf8))
            req.httpBody = body
        }
        var usedToken: String?
        if auth {
            guard let t = KeychainStore.get("accessToken") else {
                throw CompanyError(status: 401, code: "NO_TOKEN", message: tr("Chưa đăng nhập công ty"))
            }
            usedToken = t
            req.setValue("Bearer " + t, forHTTPHeaderField: "Authorization")
        }
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw CompanyError(status: 0, code: "NETWORK", message: tr("Không kết nối được tới API công ty: {0}", error.localizedDescription))
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, auth, retry {
            // Token hết hạn: làm mới một lần rồi gọi lại. Nếu lệnh khác đã làm mới rồi thì chỉ cần gọi lại.
            try await refreshOnce(usedToken: usedToken)
            return try await request(type, method, path, query: query, json: json, multipart: multipart, auth: auth, retry: false)
        }
        guard (200..<300).contains(status) else {
            let e = try? JSONDecoder().decode(CompanyErrorBody.self, from: data)
            throw CompanyError(status: status, code: e?.code, message: e?.message ?? tr("Lỗi API công ty"))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CompanyError(status: status, code: "DECODE", message: tr("Không đọc được phản hồi của API công ty: {0}", error.localizedDescription))
        }
    }
}


extension CompanyJSON {
    /// Mọi chuỗi trông như link ảnh (…jpg/jpeg/png/webp/heic, hoặc nằm dưới /uploads/) trong JSON, không trùng lặp, đúng thứ tự.
    /// Link bắt đầu bằng "/" được ghép với địa chỉ máy chủ công ty.
    func imageURLs() -> [String] {
        var out: [String] = []
        func walk(_ j: CompanyJSON) {
            switch j {
            case .string(let t):
                let low = t.lowercased()
                let isImg = [".jpg", ".jpeg", ".png", ".webp", ".heic"].contains { low.contains($0) } || low.contains("/uploads/")
                guard isImg, low.hasPrefix("http") || t.hasPrefix("/") else { return }
                let full = t.hasPrefix("/") ? "https://apiwh-dev.tinashipping.com" + t : t
                if !out.contains(full) { out.append(full) }
            case .array(let a): a.forEach(walk)
            case .object(let o): o.keys.sorted().forEach { walk(o[$0]!) }
            default: break
            }
        }
        walk(self)
        return out
    }
}


/// Báo cáo hư hỏng của một kiện (đọc từ JSON, chịu được trường thiếu).
struct CompanyDamageReport {
    let decision: String?          // RECEIVED | REJECTED
    let reportedAt: String?
    let typeNames: [String]
    let photoURLs: [String]

    init(json: CompanyJSON) {
        decision = json["decision"]?.stringValue
        reportedAt = json["reportedAt"]?.stringValue
        var names: [String] = []
        if case .array(let a)? = json["damageTypes"] {
            names = a.compactMap { $0["name"]?.stringValue ?? $0["code"]?.stringValue }
        }
        typeNames = names
        var urls: [String] = []
        if case .array(let a)? = json["photoUrls"] { urls = a.compactMap { $0.stringValue } }
        if urls.isEmpty, case .array(let a)? = json["photos"] { urls = a.compactMap { $0["url"]?.stringValue } }
        photoURLs = urls.isEmpty ? json.imageURLs() : urls
    }
}
