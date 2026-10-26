import Foundation

/// Hàng đợi ảnh label lưu TRÊN Ổ ĐĨA của iPhone: ảnh chỉ bị xóa sau khi server xác nhận đã nhận.
/// Mất mạng, server lỗi, thoát màn hình hay tắt app đều không làm mất ảnh; lần mở sau sẽ tự gửi tiếp.
/// Tên file: `<itemId>__<uuid>.jpg`
enum PhotoOutbox {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PhotoOutbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Lưu ảnh để gửi cho kiện `itemId`. Trả về false nếu ghi file thất bại.
    @discardableResult
    static func save(_ jpeg: Data, itemId: String) -> Bool {
        let name = "\(itemId)__\(UUID().uuidString).jpg"
        do { try jpeg.write(to: dir.appendingPathComponent(name), options: .atomic); return true }
        catch { return false }
    }

    static func pendingFiles() -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static var count: Int { pendingFiles().count }

    /// Gửi lần lượt từng ảnh; ảnh nào thành công thì xóa, thất bại thì giữ lại. Trả về số ảnh còn lại.
    static func flush(api: APIClient) async -> Int {
        for url in pendingFiles() {
            let name = url.deletingPathExtension().lastPathComponent
            guard let id = name.components(separatedBy: "__").first, !id.isEmpty, let data = try? Data(contentsOf: url) else {
                try? FileManager.default.removeItem(at: url); continue       // file hỏng
            }
            do {
                _ = try await api.uploadLabelPhoto(itemId: FlexID(id), jpeg: data)
                try? FileManager.default.removeItem(at: url)
            } catch let e as APIError where e.code == "ITEM_NOT_FOUND" {
                try? FileManager.default.removeItem(at: url)                  // kiện đã bị xóa trên server
            } catch {
                break                                                         // mất mạng / lỗi tạm: dừng, thử lại sau
            }
        }
        return count
    }
}
