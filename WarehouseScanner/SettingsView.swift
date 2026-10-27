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
            } footer: { Text(tr("Đăng nhập bằng tài khoản kho của công ty. Mật khẩu không được lưu trong app.")) }

            Section {
                Picker(tr("Giao diện"), selection: $theme) {
                    Text(tr("Theo hệ thống")).tag("system")
                    Text(tr("Sáng")).tag("light")
                    Text(tr("Tối")).tag("dark")
                }
                .pickerStyle(.segmented)
            } header: { Text(tr("Giao diện")) } footer: { Text(tr("Màn quét camera luôn dùng nền tối để dễ nhìn.")) }

            Section {
                Picker(tr("Ngôn ngữ"), selection: $lang.code) {
                    Text("Tiếng Việt").tag("vi")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
            } header: { Text(tr("Ngôn ngữ")) }

            Section(tr("Quy tắc mã kho đang dùng ({0})", store.rules.count)) {
                ForEach(store.rules) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.customerGroup).font(.headline)
                        Text(r.patternRegex).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(tr("Cài đặt"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Xong")) { dismiss() } } }
    }
}
