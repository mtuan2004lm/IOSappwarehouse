import Foundation
import SwiftUI

/// Trạng thái đăng nhập của app: đăng nhập THẬT vào hệ thống công ty (POST /auth/login qua CompanyAPI).
/// Token lưu trong Keychain; mật khẩu không bao giờ được lưu, chỉ nhớ tên đăng nhập.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var isSignedIn: Bool
    @Published private(set) var userEmail: String
    @Published var isLoading = false
    @Published var errorMessage: String?

    init() {
        userEmail = UserDefaults.standard.string(forKey: CompanyAPI.userKey) ?? ""
        isSignedIn = CompanyAPI.shared.isSignedIn
        // Làm mới token thất bại (hết hạn / đăng nhập nơi khác) → về màn đăng nhập
        NotificationCenter.default.addObserver(forName: CompanyAPI.sessionExpired, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isSignedIn = false }
        }
    }

    /// Tên đăng nhập đã dùng lần trước, để điền sẵn vào ô đăng nhập.
    var rememberedEmail: String { userEmail }

    func signIn(email: String, password: String) async {
        let name = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !password.isEmpty else {
            errorMessage = tr("Nhập tên đăng nhập và mật khẩu")
            Haptics.error()
            return
        }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let me = try await CompanyAPI.shared.login(username: name, password: password)
            userEmail = me.username
            isSignedIn = true
            Haptics.success()
        } catch {
            if let e = error as? CompanyError, [400, 401, 403].contains(e.status) {
                // 401 = sai thông tin; 400 VALIDATION_FAILED = mật khẩu/tên không đúng định dạng (vd quá ngắn) nên cũng không thể là đúng
                errorMessage = tr("Sai tên đăng nhập hoặc mật khẩu")
            } else {
                errorMessage = error.localizedDescription
            }
            Haptics.error()
        }
    }

    func signOut() {
        isSignedIn = false
        Task { await CompanyAPI.shared.logout() }
    }
}
