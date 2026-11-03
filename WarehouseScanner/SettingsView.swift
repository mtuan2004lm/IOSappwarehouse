import SwiftUI
import AudioToolbox
import AVFoundation

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

            Section {
                ForEach(ScanSound.allCases) { SoundRow(kind: $0) }
                Button(tr("Khôi phục âm mặc định"), role: .destructive) { ScanSound.resetAll() }
            } header: { Text(tr("Âm thanh khi quét")) } footer: { Text(tr("Chọn âm cho từng trạng thái. Bấm biểu tượng loa để nghe thử. Chọn \"Tắt\" để không phát âm.")) }

        }
        .navigationTitle(tr("Cài đặt"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Xong")) { dismiss() } } }
    }
}


/// Âm thanh theo trạng thái quét (dùng âm hệ thống của iPhone, người dùng chọn trong Cài đặt). 0 = tắt.
enum ScanSound: String, CaseIterable, Identifiable {
    case found, ting, noName, duplicate, blocked, noWarehouse, rejected, block
    var id: String { rawValue }
    var key: String { self == .rejected ? "snd_rejected2" : "snd_" + rawValue }     // rejected đổi khoá (v2) để mặc định mới là giọng đọc "Block"

    var title: String {
        switch self {
        case .found: return tr("Có trong đơn hàng")
        case .ting: return tr("Chưa có thông tin (ting)")
        case .noName: return tr("Kiện NO NAME")
        case .duplicate: return tr("Mã trùng")
        case .blocked: return tr("Bắt buộc bấm END CODE")
        case .noWarehouse: return tr("Thiếu mã kho")
        case .rejected: return tr("Công ty từ chối / lỗi")
        case .block: return tr("Kiện đang bị block")
        }
    }
    var defaultID: Int {
        switch self {
        case .found: return 1057
        case .ting, .noName: return 1103
        case .duplicate, .blocked, .noWarehouse: return 1053
        case .rejected, .block: return Self.blockVoice
        }
    }
    var current: Int { UserDefaults.standard.object(forKey: key) as? Int ?? defaultID }
    func play() { Self.play(current) }

    /// Âm đặc biệt (không phải âm hệ thống): giọng đọc "Block" (nhúng sẵn trong code, không cần thêm file vào Xcode).
    static let blockVoice = -1
    private static var voicePlayer: AVAudioPlayer?

    static func play(_ id: Int) {
        if id == blockVoice {
            guard let d = Data(base64Encoded: blockVoiceBase64) else { return }
            voicePlayer = try? AVAudioPlayer(data: d, fileTypeHint: AVFileType.m4a.rawValue)
            voicePlayer?.play()
        } else if id > 0 {
            AudioServicesPlaySystemSound(SystemSoundID(id))
        }
    }
    static func resetAll() { for k in allCases { UserDefaults.standard.removeObject(forKey: k.key) } }
    /// Các âm hệ thống iPhone có thể chọn (0 = tắt).
    static let choices: [Int] = [0, -1, 1003, 1004, 1005, 1007, 1008, 1009, 1013, 1016, 1023, 1025, 1026, 1031, 1032, 1033, 1050, 1051, 1052, 1053, 1054, 1055, 1057,
                                 1070, 1071, 1072, 1073, 1100, 1101, 1102, 1103, 1104, 1105, 1106, 1107, 1108]
}

private struct SoundRow: View {
    let kind: ScanSound
    @AppStorage private var sid: Int
    init(kind: ScanSound) {
        self.kind = kind
        _sid = AppStorage(wrappedValue: kind.defaultID, kind.key)
    }
    var body: some View {
        HStack {
            Text(kind.title)
            Spacer(minLength: 8)
            Picker(kind.title, selection: Binding(get: { sid }, set: { sid = $0; ScanSound.play($0) })) {
                ForEach(ScanSound.choices + (ScanSound.choices.contains(sid) ? [] : [sid]), id: \.self) { v in
                    Text(v == 0 ? tr("Tắt") : (v == ScanSound.blockVoice ? tr("Giọng đọc \"Block\"") : tr("Âm {0}", v))).tag(v)
                }
            }
            .pickerStyle(.menu).labelsHidden()
            Button { ScanSound.play(sid) } label: { Image(systemName: "speaker.wave.2.fill") }
                .buttonStyle(.borderless).disabled(sid == 0)
        }
    }
}

/// Giọng đọc "Block" (m4a, ~5,8 KB, mã hoá base64). Tạo bằng espeak-ng ngày 3/11/2026.
private let blockVoiceBase64 = "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"
