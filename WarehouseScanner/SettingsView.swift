import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var lang: LangStore   // đổi ngôn ngữ thì làm mới màn hình
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                LabeledContent(tr("Tài khoản công ty"), value: auth.userEmail)
                Button(tr("Đăng xuất"), role: .destructive) { dismiss(); auth.signOut() }
            } footer: { Text(tr("Đăng nhập bằng tài khoản kho của công ty. Mật khẩu không được lưu trong app.")) }

            Section {
                Picker("Ngôn ngữ / Language", selection: $lang.code) {
                    Text("Tiếng Việt").tag("vi")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
            } header: { Text("Ngôn ngữ / Language") }

            Section { LabeledContent(tr("Bản app"), value: AppStore.buildTag) }

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
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
    }
}
