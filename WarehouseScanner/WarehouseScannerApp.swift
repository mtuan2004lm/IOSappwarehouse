import SwiftUI

@main
struct WarehouseScannerApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var auth = AuthStore()
    @StateObject private var lang = LangStore()
    @AppStorage("theme") private var theme = "system"   // system | light | dark (Cài đặt > Giao diện)

    private var scheme: ColorScheme? {
        switch theme { case "light": return .light; case "dark": return .dark; default: return nil }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isSignedIn { RootView().preferredColorScheme(scheme) }
                else { LoginView().preferredColorScheme(.dark) }   // màn đăng nhập thiết kế nền tối cố định
            }
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(lang)
                .tint(.accent)
        }
    }
}

struct RootView: View {
    var body: some View {
        NavigationStack { SessionsView() }
    }
}
