import Foundation

/// Khớp chuỗi đọc được (OCR) với bộ quy tắc regex lấy từ server.
/// Cùng thứ tự và cách khớp với server: duyệt theo id tăng dần, rule đầu tiên khớp thắng, không phân biệt hoa/thường.
struct RuleMatcher {
    private struct Compiled { let rule: WarehouseRule; let regex: NSRegularExpression }
    private let compiled: [Compiled]

    init(rules: [WarehouseRule]) {
        compiled = rules.filter { $0.isActive }.sorted { $0.id < $1.id }.compactMap { rule in
            guard let re = try? NSRegularExpression(pattern: rule.patternRegex, options: [.caseInsensitive]) else { return nil }
            return Compiled(rule: rule, regex: re)
        }
    }

    var isEmpty: Bool { compiled.isEmpty }

    func match(_ text: String) -> WarehouseRule? {
        let value = Self.normalize(text)
        guard !value.isEmpty else { return nil }
        let range = NSRange(value.startIndex..., in: value)
        return compiled.first { $0.regex.firstMatch(in: value, options: [], range: range) != nil }?.rule
    }

    /// Thử từng dòng OCR (và cả đoạn ghép 2 dòng liên tiếp, vì mã kho đôi khi bị ngắt dòng).
    /// Trả về dòng khớp + rule.
    func firstMatch(inLines lines: [String]) -> (text: String, rule: WarehouseRule)? {
        let cleaned = lines.map(Self.normalizeOCR).filter { !$0.isEmpty }
        var candidates = cleaned
        if cleaned.count > 1 { for i in 0..<(cleaned.count - 1) { candidates.append(cleaned[i] + " " + cleaned[i + 1]) } }
        for c in candidates { if let r = match(c) { return (c, r) } }
        // OCR hay dính thêm chữ phía trước (vd. "USPS DELIVER TO: FDVAT HUE"): thử bỏ dần tối đa 4 từ đầu dòng
        for c in cleaned {
            let words = c.split(separator: " ").map(String.init)
            guard words.count > 1 else { continue }
            for drop in 1...min(4, words.count - 1) {
                let tail = words.dropFirst(drop).joined(separator: " ")
                if let r = match(tail) { return (tail, r) }
            }
        }
        return nil
    }

    /// Gộp khoảng trắng thừa, bỏ ký tự điều khiển.
    static func normalize(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension RuleMatcher {
    /// Sửa các lỗi OCR hay gặp trên nhãn kho trước khi khớp quy tắc:
    ///  - bỏ tiền tố "SHIP TO" / "TO" (vd. "SHIP TO SGHUE DOFA" -> "SGHUE DOFA")
    ///  - dấu gạch dưới "_" bị đọc thành khoảng trắng/gạch ngang: "SGVO A12" -> "SGVO_A12"
    ///  - số 0 bị đọc thay chữ O trong tiền tố: "SGV0_A12" -> "SGVO_A12"
    ///  - "SG FRAGILE DOFA168" (mất "_") -> "SG FRAGILE_DOFA168", nếu không sẽ bị nhầm sang FADO.VN (kinh doanh)
    /// Văn bản đã chuẩn hoá cũng là chuỗi được gửi lên server.
    static func normalizeOCR(_ s: String) -> String {
        var t = normalize(s).uppercased()
        // Bỏ nhãn "SHIP TO" / "DELIVER TO" đứng trước mã kho (chúng cùng một dòng với mã kho trên tem USPS/DHL)
        for _ in 0..<2 {
            t = t.replacingOccurrences(of: #"^((USPS|UPS|FEDEX|DHL)\s+)?(SHIP\s*TO|DELIVER(Y)?\s*TO|SHIP|TO)\s*[:\-]?\s+"#, with: "", options: .regularExpression)
        }
        t = t.replacingOccurrences(of: #"^(SGV|HNV)0"#, with: "$1O", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^(SGKYDUYEN|HNKYDUYEN|SGVO|HNVO|CHHEN)[ \-]"#, with: "$1_", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^(SG HUE|SG FRAGILE)[ \-]DOFA168"#, with: "$1_DOFA168", options: .regularExpression)
        return t
    }
}
