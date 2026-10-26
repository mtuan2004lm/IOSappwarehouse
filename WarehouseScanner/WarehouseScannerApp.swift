import SwiftUI

@main
struct WarehouseScannerApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var auth = AuthStore()
    @StateObject private var lang = LangStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isSignedIn { RootView() } else { LoginView() }
            }
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(lang)
                .preferredColorScheme(.dark)
                .tint(.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSettings = false

    var body: some View {
        NavigationStack { SessionsView() }
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
            .onAppear { if !store.hasServer { showSettings = true } }
    }
}
