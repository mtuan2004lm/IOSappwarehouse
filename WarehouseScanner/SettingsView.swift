import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var lang: LangStore   // đổi ngôn ngữ thì làm mới màn hình
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme") private var theme = "system"

    var body: some View {
        Form {
            Section {
                LabeledContent(tr("Tài khoản công ty"), value: auth.userEmail)
                Button(tr("Đăng xuất"), role: .destructive) { dismiss(); auth.signOut() }
            }

            Section {
                Picker(tr("Giao diện"), selection: $theme) {
                    Text(tr("Theo hệ thống")).tag("system")
                    Text(tr("Sáng")).tag("light")
                    Text(tr("Tối")).tag("dark")
                }
                .pickerStyle(.segmented)
            } header: { Text(tr("Giao diện")) }

            Section {
                Picker(tr("Ngôn ngữ"), selection: $lang.code) {
                    Text("Tiếng Việt").tag("vi")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
            } header: { Text(tr("Ngôn ngữ")) }

        }
        .navigationTitle(tr("Cài đặt"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Xong")) { dismiss() } } }
    }
}
