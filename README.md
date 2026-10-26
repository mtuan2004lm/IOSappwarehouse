# Kho Scanner (iOS) – kết nối với web Warehouse Tina

App Swift/SwiftUI (iOS 16+) dùng camera iPhone **thay máy quét barcode**. Phiên nhận hàng được tạo trên web; app chỉ chọn phiên đang mở rồi quét, mọi dữ liệu gửi về web qua API:

**Một màn hình quét duy nhất, tự động:** đưa nhãn vào khung *một lần*, app lấy cùng lúc **mã vạch** và **dòng mã kho in trên nhãn** (OCR), tự khớp quy tắc của web rồi gửi `POST /receiving/sessions/:id/scan` (kèm `barcode` + `detected_text`). Không hỏi xác nhận; nhãn nào không đọc đủ cả hai trong ~1 giây thì bỏ qua và quét nhãn kế tiếp. Màn hình chỉ hiển thị nhãn **thuộc kho nào** (không phân loại kinh doanh). Mất mạng thì tự giữ lại và gửi lại mỗi 4 giây. Nút **Báo hỏng** (tuỳ chọn) chụp ảnh gắn vào kiện vừa gửi.

## 1. Chạy server (máy tính)
```bash
cd ../warehouse-receiving/server
npm run db:init        # tạo thêm bảng mới (ảnh hỏng, tracking)
npm run dev
```
Server in ra dòng `Dien thoai dung dia chi: http://192.168.x.x:3000`. Nếu macOS hỏi "cho phép node nhận kết nối đến" → **Allow**. iPhone và máy tính phải cùng Wi-Fi.

## 2. Mở project Xcode
**Cách đơn giản nhất:** thư mục này đã có sẵn `WarehouseScanner.xcodeproj` → bấm đúp để mở (không cần cài thêm gì), rồi làm bước 3.

Nếu muốn tự sinh lại project:
Cách A (nhanh, khuyên dùng):
```bash
brew install xcodegen
cd WarehouseScanner-iOS
xcodegen generate
open WarehouseScanner.xcodeproj
```
Cách B (thủ công): Xcode → New Project → iOS App (SwiftUI, tên `WarehouseScanner`) → xoá `ContentView.swift` và file `...App.swift` mặc định → kéo toàn bộ file trong thư mục `WarehouseScanner/` vào project. Trong tab **Info** của target thêm: `NSCameraUsageDescription`, `NSLocalNetworkUsageDescription`, và `App Transport Security Settings → Allow Arbitrary Loads = YES`. Trong Build Settings: Swift Language Version = **5**, *Default Actor Isolation* = **nonisolated** (nếu có).

## 3. Chạy trên iPhone thật
1. Cắm iPhone, bật **Developer Mode** (Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển).
2. Xcode → target `WarehouseScanner` → **Signing & Capabilities** → chọn Team (Apple ID cá nhân là đủ).
3. Chọn iPhone ở thanh trên, bấm ▶︎. Lần đầu: Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị → tin cậy nhà phát triển.
4. Trong app: ⚙️ → nhập `http://<IP máy tính>:3000` → **Kiểm tra kết nối** (tải 4 nhóm quy tắc mã kho).

## Cấu trúc code
| File | Việc |
|---|---|
| `CameraEngine.swift` | Camera liên tục: barcode (AVFoundation) + OCR (Vision, chạy liên tục, tự lấy nét lại khi kẹt) |
| `AutoScanViewModel.swift` | Gom mã vạch + mã kho trong cửa sổ 1 giây, gửi nền, bỏ qua nhãn lỗi, tự gửi lại |
| `AutoScanView.swift` | Màn hình quét: ĐÃ GỬI to + thẻ kết quả + khung quét; nút ⋯ Dừng quét (chốt kiện) / Kết thúc phiên |
| `NewSessionView.swift` | Tạo phiên mới (giống web) |
| `SessionDetailView.swift` | Chi tiết phiên: danh sách đơn đã quét (tự cập nhật mỗi 1 giây) + nút Bắt đầu quét |
| `Localization.swift` | Đổi ngôn ngữ Việt/Anh: hàm `tr("...")` + bảng dịch `L10n.en` |
| `LoginView.swift`, `AuthStore.swift` | Màn hình đăng nhập (bản thử, chưa nối API công ty) |
| `APIClient.swift` (phần cuối: `CompanyAPI`) | Kết nối API công ty (đang làm): đăng nhập, Keychain, làm mới token, xem phiên/kiện, kiểm tra mã, tạo phiên thử, quét `trackings/scan`, ảnh label, `TrackingCutter` (cắt chuỗi tracking). Xem `warehouse-receiving/API_INTEGRATION.md` |
| `RuleMatcher.swift` | Khớp regex như server + sửa lỗi OCR (`_` bị mất, `0`/`O`) |
| `APIClient.swift` | Gọi API web |

## Kết quả hiển thị trên màn quét
- **Thẻ xanh "KHO …"**: mã có trong *Danh sách mặt hàng* của web, kèm nhóm kho đọc từ nhãn.
- **Thẻ cam "KHÔNG XÁC ĐỊNH"**: mã không có trong Danh sách mặt hàng. Mã vẫn được gửi về web và ghi là *Không xác định*.
- **Thẻ xám "BỎ QUA"**: không đọc đủ mã vạch + mã kho, hoặc mã đã quét trong phiên.

## Lưu ý khi cập nhật
Sau khi sửa code Swift: Xcode → **Run** lại để cài bản mới lên iPhone. Sau khi sửa server: `Ctrl+C` rồi `npm run dev` lại. Xem thêm lịch sử cập nhật trong `../warehouse-receiving/README.md`.

## Tự chụp ảnh label (12/10/2026)

Mỗi lần quét, app lưu khung hình camera (`CameraEngine.snapshot()`) và gửi lên kiện bằng `POST /scanned-items/:id/label-photo`. Bật/tắt bằng công tắc *Tự chụp ảnh label khi quét* trong ⚙️ (khóa `autoLabelShot`, **mặc định TẮT từ 26/10/2026**; chụp ảnh label chủ động bằng nút "Ảnh label"). Ảnh của tracking chưa có thông tin được giữ (`pendingShots`, tối đa 4) rồi gắn vào kiện khi kiện được tạo.

### Hàng đợi ảnh label (`PhotoOutbox.swift`)

Ảnh chụp ngay khi thấy mã vạch (`shotByCode`), lưu ở `Documents/PhotoOutbox/<itemId>__<uuid>.jpg` và chỉ xóa khi server xác nhận. Tự thử lại mỗi 5 giây; gửi bù khi vào màn quét hoặc mở danh sách phiên. Màn quét hiện "N ảnh label đang chờ gửi".
- **19/10/2026**: ô "Mã kho" trên thẻ SUCCESS chỉ hiện mã kho khớp quy tắc (không bao giờ hiện tracking); quy tắc mã kho không nhận tiền tố "SHIP TO/DELIVERY TO". Cần build lại app. Chi tiết trong `warehouse-receiving/CHANGELOG.md`.

## Quét vào phiên công ty (26/10/2026)

Chạm phiên công ty → "Quét vào phiên này (ghi lên công ty)". Quy trình theo rule Phần 1: tracking có thông tin → ghi 1 kiện (các tracking "ting" trước đó thành mã phụ); chưa có thông tin → "ting"; đủ 3 mà quét tiếp → chặn, bắt buộc `ENDCODE`; `ENDCODE` → kiện NO NAME (tracking đầu là tracking gốc). Mã vạch được cắt bằng `TrackingCutter` (APIClient.swift) rồi hỏi công ty lần lượt các mã ứng viên. Không còn báo FAIL (đã bỏ ô đếm FAIL). Nhóm đang chờ chỉ lưu trong bộ nhớ.

## Quy tắc mã kho cài sẵn (26/10/2026)

App không còn tải quy tắc mã kho từ server: 4 quy tắc nằm trong `AppStore.swift` (`WarehouseRule.builtIn`). Muốn thêm/sửa quy tắc: sửa danh sách này, build lại app. Thứ tự = thứ tự ưu tiên.

## Nút END CODE (26/10/2026)

Không cần quét mã END CODE: khi có tracking chưa có thông tin, màn quét hiện nút **END CODE**; bấm để chốt (đủ 3/3 thì bắt buộc bấm mới quét tiếp). Quét mã `ENDCODE` bằng camera vẫn dùng được.

## Báo hư hỏng phiên công ty (26/10/2026)

Nút "Hỏng" ở màn quét phiên công ty mở bảng Báo hư hỏng: loại hư hỏng (nhiều lựa chọn) → ảnh → Quyết định (Nhận hàng / Từ chối, nằm cuối) → Gửi. Mỗi kiện một báo cáo. Code: `CompanyDamageSheet` (`AutoScanView.swift`), `CompanyAPI.reportDamage` (`APIClient.swift`).
