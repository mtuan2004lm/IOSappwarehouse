import Foundation
import SwiftUI

/// Trạng thái đăng nhập của app.
/// LƯU Ý: hiện CHƯA nối API công ty. `signIn` chỉ kiểm tra dữ liệu nhập và cho vào (chế độ thử).
/// Khi nối API, chỉ cần thay phần thân của `AuthService.signIn` bằng lệnh gọi POST /auth/login.
/// Mật khẩu không bao giờ được lưu; chỉ nhớ email và trạng thái đã đăng nhập.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var isSignedIn: Bool
    @Published private(set) var userEmail: String
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let emailKey = "auth.email"
    private let signedInKey = "auth.signedIn"

    init() {
        let d = UserDefaults.standard
        let saved = d.string(forKey: emailKey) ?? ""
        userEmail = saved
        isSignedIn = d.bool(forKey: signedInKey) && !saved.isEmpty
    }

    /// Email đã dùng lần trước, để điền sẵn vào ô đăng nhập.
    var rememberedEmail: String { userEmail }

    func signIn(email: String, password: String) async {
        let typed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = typed.isEmpty ? tr("Khách (bản thử)") : typed   // bản thử: cho vào kể cả khi bỏ trống
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await AuthService.signIn(email: e, password: password)
            userEmail = e
            isSignedIn = true
            let d = UserDefaults.standard
            d.set(e, forKey: emailKey)
            d.set(true, forKey: signedInKey)
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    func signOut() {
        isSignedIn = false
        UserDefaults.standard.set(false, forKey: signedInKey)
    }
}

/// Chỗ duy nhất sẽ gọi API công ty khi được phép. Hiện là bản thử (chưa gọi mạng).
enum AuthService {
    static func signIn(email: String, password: String) async throws {
        try await Task.sleep(nanoseconds: 600_000_000)   // giả lập độ trễ mạng
        // TODO(nối API): POST /auth/login rồi lưu token vào Keychain.
    }
}
