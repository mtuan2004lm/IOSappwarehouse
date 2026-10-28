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

## Quy tắc quét mã (28/10/2026)

Tổng hợp từ code hiện tại (`TrackingCutter` ở `APIClient.swift`, `AutoScanViewModel.swift`, `RuleMatcher.swift`, `AppStore.swift`). Muốn đổi quy tắc nào thì sửa đúng file ghi bên cạnh rồi build lại app.

### 1. Cắt mã vạch thành tracking (`TrackingCutter.formats`)
Mã vạch được bỏ khoảng trắng/ký tự điều khiển và viết hoa, rồi thử lần lượt các mẫu (mẫu đầu khớp trước). Mã gốc luôn là ứng viên đầu tiên; mã đã cắt được thêm vào danh sách; **mã đã cắt đầu tiên** là tracking dùng khi ghi kiện (nếu không cắt được thì dùng mã gốc).

| Mẫu nhận diện | Cách cắt | Hãng |
|---|---|---|
| `420` + ZIP5 (5 số) + 20 số trở lên | bỏ 8 ký tự đầu | USPS |
| `420` + ZIP9 (9 số) + 20 số trở lên | bỏ 12 ký tự đầu | USPS |
| 20–34 số bắt đầu bằng `9` | giữ nguyên | USPS |
| `XX#########US` (2 chữ + 9 số + US) | giữ nguyên | USPS quốc tế |
| `1Z` + 16 ký tự chữ/số (kể cả nằm trong chuỗi dài) | lấy đoạn `1Z…` | UPS |
| 30–34 số | lấy **12 số cuối** | FedEx Express |
| `96` + 20 số (22 số) | lấy **15 số cuối** | FedEx Ground |
| `92` + 20 số (22 số) | lấy **20 số cuối** | FedEx SmartPost |
| đúng 12 hoặc 15 số | giữ nguyên | FedEx |
| đúng 10 số | giữ nguyên | DHL Express |
| `JD`/`JJD`/`JVGL`/`GM` + 16–20 số | giữ nguyên | DHL eCommerce |
| `TBA`/`TBC`/`TBM` + 12 số (kể cả trong chuỗi dài) | lấy đoạn `TB?…` | Amazon Logistics |

Thêm biến thể ZIP+4 vào danh sách hỏi công ty: `420` + 9 số → `xxxxx-xxxx`; 9 số → `xxxxx-xxxx`; có dấu `-` thì thêm bản không có `-`.

### 2. Luồng quét một tem (`AutoScanViewModel.sendCompany`)
Mỗi mã vạch: hỏi công ty **song song tất cả mã ứng viên** (`check-tracking-scan`), lấy mã đứng trước trong danh sách có kết quả `FOUND` hoặc `DUPLICATE`.
- **`FOUND`** (công ty đã có thông tin kiện): ghi 1 kiện (`POST /trackings/scan`). Các tracking "ting" trước đó và các mã khác cùng nằm trên tem trở thành **mã phụ** của kiện. Âm "yes".
- **`NOT_FOUND`** (chưa có thông tin): tính là **"ting"**, xếp vào hàng chờ, chờ tracking kế tiếp (hiện "Tracking n/3 chưa có thông tin").
- **`DUPLICATE`** (đã quét trước đó): không ghi, tính vào số bỏ qua, báo "Mã đã quét trong phiên".
- **Đủ 3 "ting" mà vẫn quét tiếp** → chặn, bắt buộc bấm **END CODE**.
- **END CODE** (nút trên màn quét, hoặc quét mã `ENDCODE` / `*ENDCODE*`, chỉ nhận đúng chữ `ENDCODE`): cả nhóm đang chờ không có thông tin → lấy tracking đầu làm tracking gốc, các mã còn lại là mã phụ, ghi kiện **NO NAME** (hiện "không có mã kho" nếu chưa đọc được mã kho). Không có tracking nào đang chờ thì không làm gì.
- Cùng một tem vẫn nằm trong khung camera không bị tính lại. Mất mạng thì mã được xếp hàng và tự gửi lại; lỗi khác thì tính vào số bỏ qua.

### 3. Mã kho trên tem (`WarehouseRule.builtIn` ở `AppStore.swift`)
Đọc chữ trên tem (OCR), chuẩn hoá rồi khớp theo thứ tự, **quy tắc đầu tiên khớp thắng**, không phân biệt hoa thường:

| # | Nhóm khách | Mẫu | Loại |
|---|---|---|---|
| 1 | Giaonhan247 | bắt đầu `SGKYDUYEN_` / `HNKYDUYEN_` / `SGVO_` / `HNVO_` | không kinh doanh |
| 2 | FADO 168 | bắt đầu `CHHEN_` / `SG HUE_DOFA168` / `SG FRAGILE_DOFA168` | không kinh doanh |
| 3 | MICAFI | kết thúc bằng `MCF` hoặc `MCF` + khoảng trắng | không kinh doanh |
| 4 | FADO.VN | bắt đầu `FD VAT HUE` / `SG HUE DOFA` / `HN BANGTY DOFA` / `SG FRAGILE DOFA` / `HN FRAGILE DOFA` | kinh doanh (cần kiểm tra nhập khẩu) |

Chuẩn hoá chữ OCR trước khi khớp (`RuleMatcher.normalizeOCR`): bỏ nhãn "SHIP TO / DELIVER TO / TO" (và tên hãng đứng trước); `SGV0`/`HNV0` → `SGVO`/`HNVO`; thay khoảng trắng hoặc `-` sau `SGKYDUYEN`, `HNKYDUYEN`, `SGVO`, `HNVO`, `CHHEN` bằng `_`; "SG HUE/FRAGILE DOFA16?" (đọc sai số 8) → `SG HUE_DOFA168` / `SG FRAGILE_DOFA168` (nếu không sẽ bị nhầm sang FADO.VN). Mỗi dòng OCR được thử riêng và ghép 2 dòng liền nhau; nếu vẫn không khớp thì bỏ dần tối đa 4 từ đầu dòng.

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
