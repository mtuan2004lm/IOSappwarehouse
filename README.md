# Kho Scanner (iOS) – kết nối hệ thống công ty

App Swift/SwiftUI (iOS 16+) dùng camera iPhone **thay máy quét barcode**, làm việc trực tiếp với API công ty `https://apiwh-dev.tinashipping.com/api` (Swagger: `/api/docs`). Không còn server riêng.

**Luồng dùng:** đăng nhập bằng tài khoản kho công ty → chọn phiên đang mở (hoặc tạo phiên mới) → quét. Đưa nhãn vào khung *một lần*: app lấy **mã vạch** và **dòng mã kho in trên nhãn** (OCR), cắt chuỗi tracking, hỏi công ty (`check-tracking-scan`) rồi ghi kiện (`trackings/scan`). Quy trình ting / yes / NO NAME, nút END CODE, ảnh label và báo hư hỏng xem các mục bên dưới.

## 1. Mở project Xcode
Thư mục này đã có sẵn `WarehouseScanner.xcodeproj` → bấm đúp để mở. Nếu muốn tự sinh lại: `brew install xcodegen && xcodegen generate`.

## 2. Chạy trên iPhone thật
1. Cắm iPhone, bật **Developer Mode** (Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển).
2. Xcode → target `WarehouseScanner` → **Signing & Capabilities** → chọn Team.
3. Chọn iPhone ở thanh trên, bấm ▶︎. Lần đầu: Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị → tin cậy nhà phát triển.
4. Mở app → đăng nhập bằng tài khoản công ty (tự gõ mật khẩu, app không lưu mật khẩu).

## Cấu trúc code
| File | Việc |
|---|---|
| `WarehouseScannerApp.swift` | Điểm vào: chưa đăng nhập → `LoginView`, đã đăng nhập → danh sách phiên |
| `LoginView.swift`, `AuthStore.swift` | Đăng nhập công ty thật (`POST /auth/login`) |
| `SessionsView.swift` | Phiên công ty đang mở, tạo phiên, danh sách kiện, chi tiết kiện, kiểm tra mã |
| `AutoScanView.swift` | Màn quét + nút END CODE + `CompanyDamageSheet` (báo hư hỏng) |
| `AutoScanViewModel.swift` | Gom mã vạch + mã kho trong cửa sổ 1 giây, ting / yes / NO NAME, gửi công ty, tự gửi lại khi mất mạng |
| `CameraEngine.swift` | Camera liên tục: barcode (AVFoundation) + OCR (Vision) |
| `APIClient.swift` | `CompanyAPI` (đăng nhập, Keychain, làm mới token, phiên, kiện, quét, ảnh, hư hỏng) + `TrackingCutter` |
| `AppStore.swift` | Quy tắc mã kho cài sẵn (`WarehouseRule.builtIn`) |
| `RuleMatcher.swift` | Khớp regex mã kho + sửa lỗi OCR (`_` bị mất, `0`/`O`) |
| `Localization.swift` | Việt/Anh: hàm `tr("...")` + bảng `L10n.en` |

## Kết quả hiển thị trên màn quét
- **SUCCESS (xanh)**: kiện đã ghi lên công ty (MATCHED hoặc NO NAME), kèm mã kho đọc được.
- **TING (cam)**: tracking chưa có thông tin, chờ tracking tiếp theo hoặc nút END CODE (tối đa 3).
- **MÃ TRÙNG**: tracking đã quét trong phiên.
- **Gợi ý nhỏ phía trên khung**: lý do app đang im lặng (vd. chưa thấy mã vạch, tem đã quét rồi).

## Lưu ý khi cập nhật
Sau khi sửa code Swift: Xcode → **Run** lại để cài bản mới lên iPhone. Lịch sử thay đổi nằm trong `CHANGELOG.md`.

## Quét vào phiên công ty (26/10/2026)

Chạm phiên công ty → "Quét vào phiên này". Quy trình theo rule Phần 1: tracking có thông tin → ghi 1 kiện (các tracking "ting" trước đó thành mã phụ); chưa có thông tin → "ting"; đủ 3 mà quét tiếp → chặn, bắt buộc `ENDCODE`; `ENDCODE` → kiện NO NAME (tracking đầu là tracking gốc). Mã vạch được cắt bằng `TrackingCutter` (APIClient.swift) rồi hỏi công ty lần lượt các mã ứng viên. Không còn báo FAIL (đã bỏ ô đếm FAIL). Nhóm đang chờ chỉ lưu trong bộ nhớ.

## Quy tắc mã kho cài sẵn (26/10/2026)

App không còn tải quy tắc mã kho từ server: 4 quy tắc nằm trong `AppStore.swift` (`WarehouseRule.builtIn`). Muốn thêm/sửa quy tắc: sửa danh sách này, build lại app. Thứ tự = thứ tự ưu tiên.

## Nút END CODE (26/10/2026)

Không cần quét mã END CODE: khi có tracking chưa có thông tin, màn quét hiện nút **END CODE**; bấm để chốt (đủ 3/3 thì bắt buộc bấm mới quét tiếp). Quét mã `ENDCODE` bằng camera vẫn dùng được.

## Kết thúc phiên (28/10/2026)

Có nút **Kết thúc phiên** ở 3 chỗ: menu ⋯ ở hàng dưới màn quét, màn "ĐÃ DỪNG QUÉT", và màn chi tiết phiên (nút đỏ dưới "Quét vào phiên này"). Bấm → hỏi xác nhận → gọi `PATCH /receiving-sessions/{id}` với `{"status":"CLOSED","vehicleDepartedAt":<giờ hiện tại>}` (theo Swagger) để đóng phiên trên công ty; phiên đóng rồi không quét thêm được. "Dừng quét" chỉ dừng camera trên máy, không đóng phiên. Code: `CompanyAPI.closeSession` (`APIClient.swift`), `closeSession()` (`AutoScanView.swift`). Chưa thử trên máy thật.

## Logo hãng giao hàng (28/10/2026)

Danh sách phiên và chi tiết phiên hiện **logo hãng** thay tên chữ. Logo là SVG vector nằm trong `WarehouseScanner/Assets.xcassets/logo_*.imageset` (DHL, FedEx, OnTrac, USPS, UPS, Amazon). Hãng được nhận diện theo tên/mã trong hàm `CarrierLogo.asset(name:code:)` ở cuối `SessionsView.swift`; hãng chưa có logo thì hiện tên chữ. **Thêm hãng mới:** thêm một imageset `logo_<tên>` rồi thêm một dòng nhận diện trong hàm đó.

## Báo hư hỏng phiên công ty (26/10/2026)

Nút "Hỏng" ở màn quét phiên công ty mở bảng Báo hư hỏng: loại hư hỏng (nhiều lựa chọn) → ảnh → Quyết định (Nhận hàng / Từ chối, nằm cuối) → Gửi. Mỗi kiện một báo cáo. Code: `CompanyDamageSheet` (`AutoScanView.swift`), `CompanyAPI.reportDamage` (`APIClient.swift`).

## Xem lại ảnh label trong chi tiết kiện (27/10/2026)

Màn "Chi tiết kiện" hiện hàng ảnh label đã chụp (lấy từ `labelPhotoUrls` của API công ty); chạm để xem toàn màn hình, chụm để phóng to. Kiện hư hỏng có thêm mục "Ảnh báo hư hỏng" riêng: giờ báo, loại hư hỏng, quyết định (Nhận hàng/Từ chối) và ảnh (lấy từ `GET /trackings/{id}/damage-report`).

## Đổi ngôn ngữ Việt / Anh (27/10/2026)

Mọi chữ hiển thị viết bằng `tr("câu tiếng Việt")` (câu có số dùng `{0}`, `{1}`); bản tiếng Anh nằm trong bảng `L10n.en` (`Localization.swift`). Chữ mới thiếu bản dịch sẽ hiện nguyên tiếng Việt. Đổi ngôn ngữ ở ⚙️ hoặc nút VI | EN ở màn đăng nhập. Chữ từ công ty (tên hãng, mặt hàng, lỗi của máy chủ) không dịch.

**Giao diện sáng/tối:** ⚙️ Cài đặt → Giao diện: Theo hệ thống (mặc định) / Sáng / Tối, lưu bằng `@AppStorage("theme")`, áp dụng ở `WarehouseScannerApp.swift`. Màn đăng nhập và màn quét camera luôn nền tối.
