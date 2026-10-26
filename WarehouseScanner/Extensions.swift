import SwiftUI
import UIKit

extension UIImage {
    /// Thu nhỏ để ảnh gửi nhanh (ảnh gốc iPhone vài MB).
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

/// Khung ngắm ở giữa màn hình camera; viền cam + vòng tiến trình khi đang đọc nhãn.
struct Reticle: View {
    var active = false
    var progress: Double = 0
    /// Khung hướng dẫn chỉ để căn nhãn; camera đọc TOÀN BỘ khung hình, không chỉ trong khung này.
    /// Rộng gần hết màn hình (trước đây cố định 320x200) để đặt vừa cả mã vạch lẫn dòng mã kho.
    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width - 32, 200)
            let h = max(min(geo.size.height - 8, w * 1.4), 120)
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(active ? Color.accent : Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 3, dash: [18, 10]))
                if active {
                    RoundedRectangle(cornerRadius: 20)
                        .trim(from: 0, to: progress)
                        .stroke(Color.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .animation(.linear(duration: 0.1), value: progress)
                }
            }
            .frame(width: w, height: h)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

struct PermissionDenied: View {
    @EnvironmentObject var lang: LangStore   // đổi ngôn ngữ thì làm mới màn hình
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.largeTitle)
            Text(tr("Chưa có quyền dùng camera")).font(.headline)
            Text(tr("Vào Cài đặt > Kho Scanner > bật Camera.")).font(.footnote).multilineTextAlignment(.center)
            Button(tr("Mở Cài đặt")) { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                .buttonStyle(.borderedProminent)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.navy)
        .foregroundStyle(.white)
    }
}

struct HistorySheet: View {
    @EnvironmentObject var lang: LangStore   // đổi ngôn ngữ thì làm mới màn hình
    let entries: [ScanEntry]
    var body: some View {
        NavigationStack {
            List(entries) { e in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.barcode).font(.system(.body, design: .monospaced))
                        if let t = e.warehouseText { Text(t).font(.caption).foregroundStyle(.secondary) }
                        if let n = e.note { Text(n).font(.caption).foregroundStyle(Color.accent) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(e.group ?? tr("Bỏ qua")).font(.subheadline.bold())
                            .foregroundStyle(e.status == .sent ? Color.okGreen : Color.unknownGray)
                        Text(e.time, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .overlay { if entries.isEmpty { Text(tr("Chưa quét nhãn nào")).foregroundStyle(.secondary) } }
            .navigationTitle(tr("Lịch sử quét"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
