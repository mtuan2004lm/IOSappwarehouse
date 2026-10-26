import SwiftUI

struct LoginView: View {
    @EnvironmentObject var lang: LangStore   // đổi ngôn ngữ thì làm mới màn hình
    @EnvironmentObject var auth: AuthStore
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @FocusState private var focus: Field?
    private enum Field { case email, password }

    private var canSubmit: Bool { !auth.isLoading }   // bản thử: bấm là vào, không bắt nhập

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.navy, .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    languageToggle
                    header
                    form
                    Text(tr("Bản thử · chưa kết nối hệ thống công ty"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 72)
                .padding(.bottom, 32)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            if email.isEmpty { email = auth.rememberedEmail }
            focus = email.isEmpty ? .email : .password
        }
    }

    /// Công tắc VI | EN ở góc trên phải.
    private var languageToggle: some View {
        HStack(spacing: 0) {
            Spacer()
            HStack(spacing: 2) {
                ForEach(["vi", "en"], id: \.self) { c in
                    Button { lang.code = c } label: {
                        Text(c.uppercased()).font(.footnote.weight(.heavy))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(lang.code == c ? Color.accent : Color.clear, in: Capsule())
                            .foregroundStyle(lang.code == c ? Color.white : Color.white.opacity(0.7))
                    }
                }
            }
            .padding(3).background(Color.white.opacity(0.1), in: Capsule())
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Color.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(spacing: 4) {
                Text("TinaShipping").font(.title.bold())
                Text(tr("Đăng nhập để bắt đầu nhận hàng")).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var form: some View {
        VStack(spacing: 14) {
            field(icon: "person") {
                TextField(tr("Email hoặc tên đăng nhập"), text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
            }
            field(icon: "lock") {
                Group {
                    if showPassword { TextField(tr("Mật khẩu"), text: $password) }
                    else { SecureField(tr("Mật khẩu"), text: $password) }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focus, equals: .password)
                .onSubmit { submit() }
                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(.secondary)
                }
                .accessibilityLabel(showPassword ? tr("Ẩn mật khẩu") : tr("Hiện mật khẩu"))
            }

            if let msg = auth.errorMessage {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(Color.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if auth.isLoading { ProgressView().tint(.white) }
                    Text(auth.isLoading ? tr("Đang đăng nhập…") : tr("Đăng nhập")).font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accent)
            .disabled(!canSubmit)
        }
    }

    private func field<C: View>(icon: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
            content()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        Task { await auth.signIn(email: email, password: password) }
    }
}
