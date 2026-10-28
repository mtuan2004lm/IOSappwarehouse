# NHẬT KÝ THAY ĐỔI — App iPhone quét kho (WarehouseScanner-iOS)

> Nhật ký riêng của app iOS, tách từ `warehouse-receiving/CHANGELOG.md` ngày 26/10/2026 khi tách thư mục iOS và web.
> **Quy tắc:** mỗi khi sửa code app, thêm một mục mới ở đầu phần "Lịch sử" (mới nhất ở trên). Lịch sử cũ (trước 26/10/2026) và phần server/web vẫn ở `warehouse-receiving/CHANGELOG.md`.

**Ký hiệu:** ⭐ quan trọng · 🔥 khó / dễ sai · 🧪 chỉ để test · 📱 cần build lại app trong Xcode

---

## Lịch sử thay đổi (mới nhất ở trên)

### 2026-10-28 · ⭐ 🔥 📱 Chi tiết phiên: nút sao chép mã tracking
- Mỗi kiện trong danh sách có **nút sao chép nhỏ** (icon `doc.on.doc`, 28pt) **nằm ngay kế bên mã tracking** (theo ý bạn; bản đầu đặt ở mép phải dòng, to hơn): bấm → chép **mã tracking** (`trackingNumber`) vào bộ nhớ tạm, icon đổi thành ✓ xanh 1,5 giây kèm rung nhẹ. Giữ lâu lên dòng kiện cũng ra menu **"Sao chép mã"**.
- Code: `copyTracking(_:)` + `@State copiedId` trong `CompanyTrackingsView` (`SessionsView.swift`, thêm `import UIKit` cho `UIPasteboard`); `Localization.swift` thêm 1 câu EN ("Sao chép mã" → "Copy code").
- 🔥 Chưa thử trên máy: nút `.borderless` nằm trong dòng có `NavigationLink` — bấm nút chỉ được chép, **không** được mở chi tiết kiện. Nếu bấm nút mà vẫn mở chi tiết thì báo để đổi cách làm.

### 2026-10-28 · Tài liệu: ghi lại quy tắc quét mã trong README (không đổi code)
- `README.md` thêm mục **"Quy tắc quét mã"**: (1) bảng cắt mã vạch theo hãng (`TrackingCutter`), (2) luồng quét FOUND / NOT_FOUND ("ting") / DUPLICATE / 3 ting bắt buộc END CODE / NO NAME, (3) 4 quy tắc mã kho cài sẵn và các sửa lỗi OCR. Chép từ code hiện tại; sửa quy tắc trong code thì cập nhật mục này.

### 2026-10-28 · ⭐ 🔥 📱 Danh sách phiên: hiện lại "người mở phiên" và trạm
- ⭐ Lỗi: danh sách phiên **không có dòng "mở bởi …" và trạm** vì `GET /receiving-sessions` chỉ trả `userId`/`stationId`; muốn kèm người mở phiên, trạm, hãng phải gửi `include=user,station,carrier` (Swagger ghi rõ "Present only when ?include=user was requested"; cấu trúc `user {id, username, fullName}`, `station`/`carrier {id, code, name}` khớp với model trong app). App chưa bao giờ gửi tham số này (hãng thì tra thêm bằng danh sách hãng nên vẫn hiện).
- `CompanyAPI.sessions(...)` và `CompanyAPI.session(id:)` nay gửi `include=user,station,carrier`; máy chủ từ chối thì tự gọi lại như cũ (không làm hỏng danh sách).
- 🔥 Chưa thử trên máy: tên người mở phiên hiện đúng không (dùng `fullName`, không có thì `username`).

### 2026-10-28 · ⭐ 🔥 📱 Chi tiết phiên: tiêu đề "Phiên #N" to hơn, đánh số thứ tự, kiện quét đầu tiên lên trên
- Tiêu đề "Phiên #17" trên thanh trên cùng: chữ **26pt đậm** (trước là cỡ mặc định nhỏ), đặt bằng `ToolbarItem(.principal)`.
- ⭐ Danh sách kiện nay sắp **kiện quét đầu tiên ở trên cùng** (theo ý bạn): `CompanyAPI.trackings` gửi `sort=checkedInAt&order=asc` (Swagger `GET /trackings`; mặc định máy chủ là `createdAt` giảm dần), nên sắp đúng cả khi phiên có nhiều trang (tải thêm 30 kiện/lần). Mỗi kiện có **số thứ tự theo lúc quét**: 1 = kiện quét đầu tiên (dòng trên cùng), tăng dần xuống dưới; `rowNumber` = vị trí dòng. Số nằm **giữa ô theo chiều dọc** ở bên trái, chữ to hơn (`title3` đậm). ⭐ **Mỗi thông tin một dòng** trong từng kiện (trước đó nhãn "Kiện không xác định" và dòng chữ xám nằm chung một hàng nên bị ngắt dòng xấu): dòng 1 mã tracking · dòng 2 "khách …" và "kệ …" (chỉ khi có) · dòng 3 trạng thái + giờ nhập (vd "Đã nhập · 26/10 15:20") · **dòng cuối** nhãn "Kiện không xác định"/"HƯ HỎNG" (chỉ khi có; theo ý bạn để ở cuối). Số này chỉ để đếm trên màn hình, không phải mã của hệ thống. 🔥 Chưa thử trên máy: máy chủ nhận `sort`/`order` đúng như Swagger không (nếu lỗi thì danh sách kiện báo lỗi).
- Không đổi API, không đổi `Localization.swift`.

### 2026-10-28 · ⭐ 🔥 📱 Bộ lọc danh sách phiên: cả 4 bộ lọc gọi API (manager dặn)
- ⭐ Trước đây chỉ **Hãng** và **Trạng thái** gọi API; **Cửa** và **Giờ xe đến** lọc trên máy trong 50 phiên đã tải (phiên cũ ngoài 50 phiên đầu sẽ không bao giờ hiện). Nay cả 4 đều gửi lên `GET /receiving-sessions`: `carrierId`, `status`, `dockGate` (khớp đúng), `openedFrom`/`openedTo` (Swagger: "filters vehicleArrivedAt" = giờ xe đến; gửi ISO, từ 00:00 ngày bắt đầu đến 23:59:59 ngày kết thúc theo giờ máy).
- `CompanyAPI.sessions(status:carrierId:dockGate:arrivedFrom:arrivedTo:)` (`APIClient.swift`); `shown` nay chính là danh sách máy chủ trả về, bỏ lọc trên máy.
- Đổi cửa / ngày → tự gọi lại API (`onChange` fGate, fFrom, fTo). Chỉ nhận kết quả của lần gọi mới nhất (`loadToken`), vì "Xoá lọc" đổi nhiều bộ lọc cùng lúc.
- Danh sách cửa trong menu nhớ các cửa đã thấy (`knownGates`): lọc theo một cửa thì máy chủ chỉ trả phiên của cửa đó, nhưng vẫn chọn lại được cửa khác. Cửa chưa từng hiện trong lần tải nào thì chưa có trong menu (API không có endpoint danh sách cửa).
- 🔥 Chưa thử trên máy: máy chủ có nhận `dockGate` và `openedFrom/To` đúng như Swagger không; cách máy chủ hiểu mốc giờ (UTC `Z`) so với giờ Việt Nam/Oregon; giới hạn vẫn 50 phiên mỗi lần (API cho tối đa 500).

### 2026-10-28 · ⭐ 📱 Logo hãng giao hàng thay chữ (theo web của manager)
- ⭐ Thêm **6 logo vector** vào `Assets.xcassets` (mỗi logo một imageset `logo_*`, bật Preserve Vector Data): `logo_dhl`, `logo_fedex`, `logo_ontrac`, `logo_usps`, `logo_ups`, `logo_amazon`. File SVG gốc do bạn gửi; mình chỉ dọn cho Xcode đọc chắc (đưa màu từ `<style>`/class vào thuộc tính, bỏ metadata Inkscape/Illustrator, đặt kích thước px = viewBox), hình không đổi.
- Danh sách phiên: tên hãng màu cam được thay bằng **logo, không có nền trắng** (theo ý bạn). ⭐ **Giao diện tối:** Amazon, OnTrac, USPS có thêm bản `*_dark.svg` (chữ tối đổi sang **trắng**, giữ nguyên biểu tượng/màu cam/đỏ) đặt trong cùng imageset với `appearances: luminosity=dark` — Xcode tự chọn bản theo giao diện sáng/tối của app (lỗi ban đầu: chữ "amazon" màu đen tuyền biến mất trên nền tối, chỉ còn nụ cười cam). DHL, UPS và **FedEx** chỉ có một bản, giữ **đúng màu gốc** (FedEx: "Fed" tím + "Ex" cam; theo ý bạn đã bỏ bản chữ trắng, nên ở giao diện tối chữ tím hơi tối nhưng vẫn là màu thương hiệu). Chi tiết phiên: logo to hơn nằm trên số "đã quét / hãng khai".
- Nhận diện hãng theo **tên (hoặc mã)** hãng, không phân biệt hoa thường: có "fedex" (FedEx, FEDEX EXPRESS, FEDEX GROUND) → FedEx; "dhl"; "ontrac"; "amazon" (Amazon Logistics/Package/Pallet) → Amazon; từ riêng "usps" → USPS; từ riêng "ups" → UPS. **Hãng chưa có logo (vd. "Other") vẫn hiện tên chữ như cũ.**
- Code: struct `CarrierLogo` thêm cuối `SessionsView.swift` (không tạo file Swift mới); không đổi API, không đổi `Localization.swift`.
- Bộ lọc "Hãng" vẫn là chữ (menu hệ thống không hiện ảnh được).
- 🔥 Chưa thử trên máy: (1) Xcode có hiện đúng cả 6 SVG không (nếu logo nào trống/đen thì báo để đổi sang PNG); (2) tên hãng thật trên hệ thống khớp quy tắc nhận diện ở trên; (3) kích thước logo vừa mắt (USPS dài nên khá nhỏ).

### 2026-10-28 · ⭐ 🔥 📱 Chi tiết phiên: gọn lại theo góp ý của manager
- **Bỏ** dòng "Đang dùng phiên này / Chọn dùng phiên này" (chức năng cũ chỉ ghi nhớ một phiên trên máy, không còn ai dùng: màn quét lấy phiên từ chính màn đang mở) và dấu ✓ tương ứng ở danh sách phiên; bỏ 2 `@AppStorage` `company.selectedSessionId/Label`.
- **Số "đã quét / hãng khai"**: bỏ chữ ghi chú, số **rất to (52pt), canh giữa**, xanh khi đủ, vàng khi thiếu.
- ⭐ **Một ô quét/gõ mã** thay khung "Kiểm tra mã với công ty": bỏ tiêu đề và nút "Kiểm tra mã (không ghi)"; gõ/dán/quét bằng đầu đọc rồi nhấn Search/Enter → nếu mã đã nằm trong danh sách đã quét thì hiện ✓ xanh **"Đã có trong danh sách đã quét"**, không thì "Chưa có trong danh sách đã quét". Cách tìm: (1) trong các kiện của phiên đã tải (mã chính và mã phụ, qua `TrackingCutter.candidates`); (2) nếu chưa thấy, hỏi công ty `check-tracking-scan` (tối đa 4 mã ứng viên), `DUPLICATE` = đã quét rồi (có thể ở phiên khác). Không còn dòng JSON/chuỗi FOUND/NOT_FOUND.
- Nút "Quét vào phiên này" đổi thành **"Tiếp tục quét"**.
- Bỏ tiêu đề "Kiện trong phiên" và dòng "Phiên này chưa có kiện nào."
- ⭐ Nút **Kết thúc phiên** chuyển xuống **cuối màn hình** (sau danh sách kiện), vẫn luôn hỏi xác nhận trước khi đóng.
- Màn này nay tự tải lại mỗi lần hiện (`onAppear`): lấy lại phiên `GET /receiving-sessions/{id}` (hàm mới `CompanyAPI.session(id:)`) để số đã quét cập nhật sau khi quay về từ màn quét, rồi tải lại danh sách kiện.
- `Localization.swift`: thêm 2 câu EN, bỏ 11 câu không còn dùng. Không đổi logic quét.
- 🔥 Chưa thử trên máy: ô quét có tìm đúng mã đã quét ở phiên khác không; `GET /receiving-sessions/{id}` có giải mã được `CompanySession` không (nếu lỗi thì số đã quét giữ như lần tải danh sách).

### 2026-10-28 · ⭐ 🔥 📱 Danh sách phiên: bộ lọc, icon, số đã quét/khai to và có màu (góp ý của manager)
- Bỏ tiêu đề "Phiên đang mở" (danh sách nay có thể hiện cả phiên đã đóng).
- ⭐ **Bộ lọc giống web** ở đầu danh sách (thanh cuộn ngang): **Hãng**, **Trạng thái** (Tất cả / Đang mở / Đã đóng), **Cửa**, **Giờ xe đến** (từ ngày – đến ngày), nút **Xoá lọc** (hiện khi đang lọc). Mặc định tất cả (giống web). Hãng và trạng thái lọc ở máy chủ (`GET /receiving-sessions?status=&carrierId=`, hàm mới `CompanyAPI.sessions(status:carrierId:)` thay `openSessions()`); cửa và giờ xe đến lọc ngay trên máy (theo `dockGate` và `vehicleArrivedAt` của các phiên đã tải; danh sách cửa lấy từ các phiên đang hiện).
- **Icon thay chữ:** "cửa D2" → icon cửa `door.left.hand.closed` + D2; thêm icon xe `box.truck` trước biển số/loại xe; "xe đến 28/10 11:29" → icon đồng hồ `clock` + giờ. Giữ nguyên "mở bởi …".
- ⭐ **Số "đã quét / hãng khai"** to hơn (30pt, đậm); **xanh khi X ≥ Y** (đủ kiện), **vàng khi X < Y** (còn thiếu); không có số khai thì để màu thường. Cùng màu ở dòng "Đã quét / hãng khai" trong chi tiết phiên.
- `SessionsView.swift`: thêm `filterBar`, `DateRangeSheet` (cuối file, không tạo file Swift mới), `coDetailText`/`coExtraText`/`coCountColor`; `Localization.swift`: thêm 12 câu EN, bỏ 3 câu không còn dùng.
- **Mỗi thông tin một dòng** (theo ý bạn, sau khi xem bản đầu): cửa · người giao (icon vô lăng `steeringwheel`, khác icon người của "mở bởi") · xe (biển số · loại xe) · giờ xe đến · trạm (icon `building.2`) · mở bởi (icon `person.crop.circle`); dòng nào không có dữ liệu thì không hiện. Hàm `coInfoRows`/`infoRow` thay `coDetailText`/`coExtraText`.
- 🔥 Chưa thử trên máy: (1) máy chủ có nhận `carrierId` cùng `status` (theo Swagger có); (2) danh sách chỉ tải 50 phiên (limit 50), nếu máy chủ trả phiên cũ trước thì "Tất cả" có thể thiếu phiên mới; (3) icon `box.truck`/`door.left.hand.closed` cần iOS 16 trở lên (đúng với app).

### 2026-10-28 · ⭐ 📱 Bỏ các dòng chữ nhỏ dùng khi lập trình (chuẩn bị cho nhân viên dùng thật)
- Bỏ chú thích nhỏ dưới các mục: danh sách phiên ("Chạm một phiên…", "Đang chọn…"), chi tiết phiên ("Chỉ xem. Chưa ghi gì lên công ty.", "Chỉ hỏi công ty mã này đã có chưa…", "Mỗi kiện quét ở đây là kiện THẬT…", chú thích dưới nút Kết thúc phiên), màn Tạo phiên ("Tạo phiên THẬT trên apiwh-dev…"), Cài đặt ("Đăng nhập bằng tài khoản kho…", "Màn quét camera luôn dùng nền tối…").
- Bỏ mục **"Quy tắc mã kho đang dùng (4)"** (hiện regex) khỏi Cài đặt; quy tắc vẫn chạy bình thường (`AppStore.swift`, `WarehouseRule.builtIn`).
- Hộp xác nhận tạo phiên: "Sẽ ghi một phiên thật lên apiwh-dev và không xoá được." → "Phiên mới sẽ được tạo trên hệ thống công ty." (EN: The new session will be created on the company system.).
- Sửa `SessionsView.swift`, `SettingsView.swift`, `Localization.swift` (xoá 11 câu dịch không còn dùng, thêm 1). Không đổi logic.
- Còn giữ (chưa hỏi): khung "Kiểm tra mã với công ty" và dòng "Chọn dùng phiên này" trong chi tiết phiên.

### 2026-10-28 · ⭐ 🔥 📱 Bản 2 (Build 2): dọn code trước khi phát cho nhân viên
- ⭐ **Khai báo mã hóa:** thêm `ITSAppUsesNonExemptEncryption = NO` (app chỉ dùng HTTPS có sẵn của iOS). Từ bản này Apple không hỏi "Missing Compliance" trên TestFlight nữa, người có quyền Developer đưa build vào nhóm được mà không cần manager trả lời. Sửa `Config/Info.plist`, `project.yml` và `project.pbxproj` (`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`, cả Debug và Release).
- **Bỏ ATS thừa:** xoá `NSAllowsArbitraryLoads` (cho phép HTTP tự do) khỏi `Config/Info.plist` và `project.yml`; app chỉ gọi API `https://`. 🔥 Nếu sau này có địa chỉ ảnh/API dạng `http://` thì sẽ không tải được.
- **Bỏ `NSLocalNetworkUsageDescription`** ("kết nối server trong mạng nội bộ") khỏi `project.pbxproj` và `project.yml` vì không còn dùng server nội bộ.
- **Sửa chữ xin quyền ảnh** (`NSPhotoLibraryUsageDescription`): "Chọn ảnh nhãn hoặc ảnh hàng hỏng để gửi lên công ty." (trước: "…chỉ dùng khi chạy trên giả lập").
- **Bỏ dòng debug "OCR: …"** trên màn quét (`AutoScanView.swift`); biến `ocrDebug` trong `AutoScanViewModel` vẫn còn nhưng không hiển thị.
- Chỉ sửa đúng các dòng trên trong `project.pbxproj` (các dòng ký app, profile `WH Scanner 3PL - AppStore` giữ nguyên).
- 📱 Việc của người build: tăng **Build** lên 2 (General → Build), Archive, Export, Transporter. Chưa đổi API sang bản thật (chờ địa chỉ từ manager).

### 2026-10-28 · ⭐ 🔥 📱 Thêm nút "Kết thúc phiên" (đóng phiên trên công ty)
- Trước đó mình đã bỏ nút này vì tưởng API công ty chưa có lệnh đóng phiên; thực tế tài liệu API có `PATCH /receiving-sessions/{id}` (đổi `status` OPEN/CLOSED), nên nay thêm lại.
- `APIClient.swift`: `CompanyAPI.closeSession(id:)` gọi `PATCH /receiving-sessions/{id}` body `{"status":"CLOSED","vehicleDepartedAt":"<giờ hiện tại, UTC>"}` đúng theo Swagger (đã đọc `/api/docs` ngày 28/10/2026: `status` OPEN|CLOSED, `vehicleDepartedAt` "thường đặt cùng status=CLOSED"). Không giải mã phiên trả về, tránh báo lỗi sau khi đã đóng.
- `AutoScanView.swift`: nút **Kết thúc phiên** ở menu ⋯ (màn quét) và ở màn "ĐÃ DỪNG QUÉT"; luôn hỏi xác nhận ("Phiên #… sẽ được đóng trên công ty, không quét thêm được. Đã quét … kiện."); thành công thì tự thoát màn quét, lỗi thì hiện thông báo "Không đóng được phiên" kèm lý do. "Dừng quét" vẫn chỉ dừng trên máy, không đổi gì trên công ty.
- `SessionsView.swift` (màn chi tiết phiên `CompanyTrackingsView`): thêm nút đỏ **Kết thúc phiên** dưới nút "Quét vào phiên này" (chỉ khi phiên đang OPEN), cùng hộp xác nhận và thông báo lỗi như bên màn quét; đóng xong tự quay về danh sách và bỏ chọn phiên nếu đó là phiên đang chọn.
- `SessionsView.swift`: danh sách phiên nay tải lại mỗi lần quay về màn này (`onAppear`, trước đây chỉ tải một lần), nên phiên vừa đóng biến mất khỏi "Phiên đang mở".
- `Localization.swift`: thêm 5 câu tiếng Anh (End session / End session? / nội dung xác nhận / Could not end the session / chú thích dưới nút).
- 🔥 Chưa thử trên máy thật: cần thử trên phiên thử (đóng xong công ty không cho quét thêm: lỗi `SESSION_CLOSED`; Swagger cho phép PATCH `status: OPEN` để mở lại phiên nhưng app chưa có nút mở lại; nếu cần thì mở lại trên web). Nếu API trả 400/403 vì thiếu trường hoặc thiếu quyền, thông báo lỗi sẽ hiện nguyên văn để biết sửa gì.
- Lưu ý: sau khi đóng, màn chi tiết phiên (phía sau) vẫn còn nút "Quét vào phiên này" cho đến khi quay về danh sách và vào lại; quét vào phiên đã đóng sẽ báo lỗi.

### 2026-10-28 · ⭐ 🔥 📱 Chuẩn bị phát hành: đổi Bundle ID và Team theo tài khoản công ty
- Bundle ID `com.tina.warehousescanner` → **`com.wh.internal`** (khớp app đã tạo sẵn trên App Store Connect: tên "WH Scanner 3PL", SKU WH-SCANNER-IOS-001, Apple ID 6825729096).
- Team (`DEVELOPMENT_TEAM`) `XJV6B4PX32` → **`4A2CPW6M9J`** (manager gửi). Sửa ở `project.pbxproj` (Debug + Release) và `project.yml`.
- Ký app: để Automatic; cần Apple ID của người build được mời vào team 4A2CPW6M9J (hoặc có khóa riêng của chứng chỉ .cer) — CHƯA xác nhận.
- Tên dưới icon vẫn "Warehouse Tina" (không bắt buộc khớp tên trên App Store).
- 📱 Sau khi đổi, app cài trên máy là app MỚI (Bundle ID khác): xoá bản cũ, đăng nhập lại. Cần Clean Build Folder.

### 2026-10-28 · 📱 Nút quét: bỏ chữ "(ghi lên công ty)"
- Nút trong màn chi tiết phiên: "Quét vào phiên này (ghi lên công ty)" → "Quét vào phiên này" (EN "Scan into this session"). Dòng chú thích bên dưới (kiện quét là kiện THẬT, không xoá được) giữ nguyên. Sửa `SessionsView.swift`, `Localization.swift`.

### 2026-10-28 · 📱 Chi tiết kiện: bỏ chữ "Khớp ·" ở dòng Khớp đơn
- Dòng "Khớp đơn" chỉ hiện tên hàng và mã đơn, vd "Kem chống nắng Anessa Perfect UV 60ml (đơn 990001)". Chỉ khi công ty chưa trả tên hàng mới ghi "Khớp". Sửa `SessionsView.swift` (`coMatchedText`).

### 2026-10-27 · ⭐ 🔥 📱 Quét: mã còn lại trên tem luôn được gửi kèm làm mã phụ
- Trước: tracking đầu tiên công ty có (FOUND) → ghi kiện chỉ với các mã đã "ting" trước đó; các mã khác cùng nằm trên tem bị bỏ qua (không gửi làm mã phụ).
- Nay: khi một mã FOUND, `additionalTrackingNumbers` = mã đã ting + mọi mã khác cùng thấy trong khung (đã cắt qua `TrackingCutter`, bỏ trùng với mã chính và các mã ứng viên của nó). Mã chính vẫn là mã công ty biết (FOUND).
- Sửa `AutoScanViewModel.swift` (nhánh FOUND của `sendCompany`) và chú thích.
- 🧪 Cần thử: tem 3 mã vạch, mã đầu có trong danh sách → trên web kiện phải có 2 mã phụ; thẻ kết quả ghi "+2 mã phụ".
- Lưu ý: công ty không cho xoá/sửa kiện đã ghi, nên thử trên tem thật trong phiên thử.

### 2026-10-27 · ⭐ 🔥 📱 Chi tiết kiện: "Khớp đơn" hiện tên hàng như web (sửa lỗi vẫn báo NO_NAME)
- Nguyên nhân: app gọi `GET /trackings` và `GET /trackings/{id}` KHÔNG kèm `include`, nên công ty không trả `orderItems` (chỉ trả `orderItemCount`); web gọi kèm `include=orderItems,holdCaseItems…`. Vì vậy app tưởng kiện chưa có dòng hàng và ghi thô "NO_NAME" (bản 14:12 của kiện TBA334169588754).
- Sửa: cả danh sách và chi tiết kiện gọi kèm `include=orderItems,holdCaseItems`; nếu công ty từ chối tham số này thì tự gọi lại như cũ (không vỡ màn hình). Thêm `hasOrderLines` (dựa `orderItemCount` hoặc `orderItems`) dùng cho `isUnknown`.
- Dòng "Khớp đơn" nay: "Khớp · Kem chống nắng Anessa Perfect UV 60ml (đơn 990001)"; mục "Hàng trong kiện" cũng hiện lại nhờ có `orderItems`.
- Dòng "Khớp đơn" trình bày dọc (nhãn trên, giá trị dưới, chữ to và đậm hơn, tự xuống dòng) để đọc trọn tên hàng dài (`rowStacked`).
- Chưa xác minh tên đúng của tham số include (web cắt chữ "holdCa…"); đã có phương án gọi lại.
- Sửa `APIClient.swift`, `SessionsView.swift`, `Localization.swift`.

### 2026-10-27 · ⭐ 📱 NO NAME theo đúng cách web tính (kiện đã có dòng hàng thì KHỚP)
- Phát hiện từ JSON + ảnh web phiên 17: cả 6 kiện đều có `matchStatus: NO_NAME`, nhưng web chỉ gắn "Kiện không xác định" cho 4 kiện **chưa có `orderItems`**; kiện 322, 323 có dòng hàng khai báo nên web coi là khớp danh sách (kiện 323 chỉ gắn nhãn DAMAGED). App trước đó hiển thị thẳng `matchStatus` nên báo NO NAME sai so với web.
- Thêm `CompanyTracking.isUnknown` = NO_NAME **và** không có dòng hàng. Danh sách kiện: nhãn NO NAME chỉ hiện khi `isUnknown`; thêm nhãn đỏ **HƯ HỎNG** cho kiện `condition == DAMAGED` (giống nhãn DAMAGED của web). Chi tiết kiện: "Khớp đơn" = Khớp nếu đã có dòng hàng.
- Đổi tên hiển thị: danh sách + chi tiết kiện + kết quả kiểm tra mã ghi **"Kiện không xác định"** (EN "Unknown parcel") thay vì "NO NAME", đúng cách gọi của web. Thẻ NO NAME lúc quét (quy trình END CODE) giữ nguyên.
- Không đổi màn quét tức thời (vẫn theo kết quả công ty trả lúc quét) và không đổi dữ liệu gửi đi.
- ❓ Chưa rõ vì sao công ty để `matchStatus` NO_NAME cả khi đã liên kết dòng hàng; app chỉ đổi cách hiển thị cho khớp web.
- Sửa `APIClient.swift`, `SessionsView.swift`, `Localization.swift`.

### 2026-10-27 · ⭐ 📱 Chi tiết kiện: mục "Ảnh báo hư hỏng" (ảnh + loại + quyết định + giờ báo)
- Kiện `condition == DAMAGED` hiện mục **Ảnh báo hư hỏng**, tách riêng khỏi **Ảnh label đã chụp** (như web: tab "Ảnh tem" và tab "Hư hỏng").
- Gồm: **Đã báo lúc**, **Loại hư hỏng** (tên công ty, vd "Seal broken / Rách seal"), **Quyết định** (Nhận hàng / Từ chối), hàng ảnh (chạm xem lớn, phóng to).
- Endpoint `GET /trackings/{id}/damage-report` (chỉ đọc) — ĐÃ xác minh bằng JSON thật kiện 323: `{decision, reportedAt, damageTypes[{code,name}], photos[…], photoUrls[…]}`. Bỏ phần dò JSON thô tạm.
- Sửa `APIClient.swift` (`damageReport`, `CompanyDamageReport`), `SessionsView.swift`, `Localization.swift`.
- ❗ Đọc báo cáo công ty chỉ có 1 báo cáo mỗi kiện; ảnh gửi lại sẽ THAY toàn bộ ảnh cũ (web nhắc) — app chỉ đọc, không đụng.

### 2026-10-27 · ⭐ 📱 Chi tiết kiện: xem lại ảnh label đã chụp
- Màn "Chi tiết kiện" có mục **Ảnh label đã chụp**: hàng ảnh nhỏ cuộn ngang; chạm vào → xem toàn màn hình, vuốt ngang đổi ảnh, chụm 2 ngón phóng to (tối đa 6 lần), chạm đúp về cỡ gốc, nút X đóng.
- Dữ liệu: API danh sách/chi tiết kiện đã trả `labelPhotoUrls` (link đầy đủ `https://apiwh-dev…/uploads/trackings/<id>/label-….jpg`) và `labelPhotos[{id,url,…}]` (xác nhận từ JSON thật phiên 17, 26–27/10). App đọc `labelPhotoUrls`, thiếu thì lấy `labelPhotos[].url`; hiển thị bằng `AsyncImage`.
- Sửa `APIClient.swift` (thêm `labelPhotoURLs`, `CompanyPhotoRef` thay `CompanyAnyJSON`), `SessionsView.swift` (mục ảnh + `RemotePhoto`/`PhotoViewer`/`ZoomablePhoto`, không thêm file mới), `Localization.swift` (2 chuỗi).
- 🧪 Cần thử trên iPhone: kiện `TBA334169588754` (id 323, 1 ảnh), `383433054030` (id 321, 2 ảnh). Nếu ảnh không hiện (biểu tượng cảnh báo) có thể link `/uploads` cần đăng nhập → đổi sang tải kèm token.
- ❓ Ảnh **hư hỏng** chưa làm: JSON danh sách kiện KHÔNG có ảnh hư hỏng (kiện 323 `condition: DAMAGED` nhưng không có trường ảnh) nên cần biết endpoint riêng mà web gọi khi mở tab Hư hỏng.

### 2026-10-27 · 📱 Đăng nhập sai: báo "Sai tên đăng nhập hoặc mật khẩu"
- Trước: hiện lỗi kỹ thuật "Invalid credentials (HTTP 401, UNAUTHORIZED)". Nay: lỗi 400/401/403 khi đăng nhập → "Sai tên đăng nhập hoặc mật khẩu" (EN "Incorrect username or password"). Lỗi mạng/máy chủ khác vẫn hiện nguyên nhân thật.
- Cố ý gộp chung tên đăng nhập và mật khẩu (không nói rõ sai cái nào) vì API chỉ trả 401 chung và để không lộ tên nào tồn tại. Sửa `AuthStore.swift`, `Localization.swift`.
- Bổ sung: nhập mật khẩu ngắn/lạ (vd `hâhhaaa`, 7 ký tự có dấu) API trả **400 VALIDATION_FAILED** thay vì 401 nên trước đó vẫn hiện lỗi kỹ thuật; nay 400 cũng báo cùng câu. Chưa xác minh quy tắc chính xác của API (có thể mật khẩu tối thiểu 8 ký tự).

### 2026-10-27 · 📱 Bỏ nút "Tạo phiên mới" cuối danh sách (đã có dấu +)
- Danh sách "Phiên đang mở" không còn nút "Tạo phiên mới" ở cuối; tạo phiên bằng dấu + trên thanh trên cùng (nhãn trợ năng "Tạo phiên mới").
- Hộp xác nhận "Tạo phiên trên công ty?" → "Tạo phiên?" (EN "Create a session?"). Sửa `SessionsView.swift`, `Localization.swift`.

### 2026-10-27 · 📱 Màn chính: tiêu đề "Phiên đang mở"
- "Phiên đang mở trên công ty" → "Phiên đang mở" (EN: "Open sessions"). Sửa `SessionsView.swift`, `Localization.swift`.

### 2026-10-27 · 📱 Màn tạo phiên: bỏ chữ "thử"
- Tiêu đề và nút "Tạo phiên thử" → "Tạo phiên" (EN: "Create session"). Sửa `SessionsView.swift`, `Localization.swift`. Dòng chú thích bên dưới (tạo phiên THẬT, không xoá được) giữ nguyên.

### 2026-10-27 · 📱 Cài đặt: tiêu đề mục ngôn ngữ đổi theo ngôn ngữ
- Trước: luôn "Ngôn ngữ / Language". Nay: tiếng Việt → "Ngôn ngữ", English → "Language" (`tr("Ngôn ngữ")` + 1 chuỗi EN). Sửa `SettingsView.swift`, `Localization.swift`.
- Màn đăng nhập vẫn có nút VI | EN riêng, không đổi.

### 2026-10-27 · 📱 Đổi tên app thành "Warehouse Tina"
- Tên dưới icon: `INFOPLIST_KEY_CFBundleDisplayName` (2 chỗ trong `project.pbxproj`) và `project.yml`: "Kho Scanner" → "Warehouse Tina".
- Đổi chữ hướng dẫn quyền camera ("Cài đặt > Warehouse Tina > bật Camera", VI + EN) và tiêu đề `README.md`.
- 📱 Cần build lại và cài đè app để tên mới hiện trên màn hình chính.

### 2026-10-27 · 📱 Danh sách phiên: chữ to hơn
- Màn "Phiên đang mở trên công ty": số phiên title3, tên hãng headline, dòng cửa/tài xế/ngày xe đến subheadline (trước caption), số đếm 6/23 title2. Chữ tự to theo cỡ chữ iOS của máy.
- Sửa `SessionsView.swift`.

### 2026-10-27 · 📱 Danh sách kiện: mã tracking dài hiển thị đủ trên 1 dòng
- Trước: mã dài (vd 32 số, USPS 420…) bị cắt "…" vì chung dòng với nhãn NO NAME.
- Nay: mã tracking ở dòng riêng ăn hết chiều ngang, tự thu nhỏ chữ (tối đa 50%) để vừa 1 dòng; nhãn NO NAME chuyển xuống dòng thông tin.
- Sửa `SessionsView.swift` (danh sách kiện trong phiên). Màn chi tiết kiện vẫn xuống dòng để hiện đủ mã.
- 🧪 Thử trên iPhone với mã 32 số; nếu chữ quá nhỏ khó đọc thì cho phép mã xuống 2 dòng.

### 2026-10-27 · ⭐ 📱 Nhân viên tự chọn giao diện Sáng / Tối / Theo hệ thống
- Cài đặt → **Giao diện** (mặc định Theo hệ thống). Trước đây app ép nền tối cố định.
- Lưu `@AppStorage("theme")` (system|light|dark); áp dụng `preferredColorScheme` ở `WarehouseScannerApp.swift`.
- Màn đăng nhập và màn quét camera giữ nền tối cố định (thiết kế nền tối, chữ trắng trên camera).
- Thêm 5 chuỗi VI/EN vào `Localization.swift`. Không thêm file Swift mới.
- 🧪 Cần thử trên iPhone: đổi 3 chế độ, kiểm tra danh sách phiên, chi tiết kiện, Cài đặt ở chế độ Sáng (chữ/màu cam, đỏ, xanh còn dễ đọc).

### 2026-10-27 · 📱 Đổi icon app thành logo TiNa (TN)
- Icon 1024×1024 dựng từ phần biểu tượng TN (máy bay + chữ TN) của logo, nền trắng, căn giữa, chừa lề cho góc bo iOS.
- Thêm `Assets.xcassets/AppIcon.appiconset` (AppIcon.png + Contents.json); đặt `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` trong `project.pbxproj` và `project.yml`.
- Lưu ý: logo gốc chỉ 216×50 px nên icon hơi mềm khi phóng to; có file ≥1024 px/SVG sẽ làm lại nét hơn.

### 2026-10-27 · 📱 Logo TiNa Shipping ở màn đăng nhập
- ⭐ Màn đăng nhập hiện logo TiNa Shipping (đặt trong khung trắng bo góc vì chữ "TiNa" màu xanh đậm, khó đọc trên nền tối) thay cho hình hộp và chữ "TinaShipping". File: `LoginView.swift`.
- 🔥 Dự án trước đây **chưa có thư mục hình ảnh**: thêm `WarehouseScanner/Assets.xcassets` (`LogoTina.imageset`, ảnh 648×150 = bản 216×50 phóng 3 lần, đặt ở ô @3x) và khai báo trong `WarehouseScanner.xcodeproj/project.pbxproj` (tham chiếu thư mục + mục Resources). Chạy `xcodegen generate` vẫn tự nhận thư mục này.
- Logo gốc chỉ 216×50 pixel nên đủ cho màn đăng nhập nhưng chưa đủ làm icon app (cần 1024×1024). Khi có file lớn hơn: thêm `AppIcon.appiconset` vào cùng `Assets.xcassets`. Chưa build Xcode.

### 2026-10-27 · 📱 Bỏ dòng "Bản app" khỏi Cài đặt
- Xoá mục "Bản app" trong `SettingsView.swift`, hằng `AppStore.buildTag` và bản dịch "Bản app" trong `L10n.en` (không còn dùng). Muốn biết iPhone đang chạy bản nào thì xem mục mới nhất của file này. Chưa build Xcode.

### 2026-10-27 · ⭐ 📱 Chuyển ngôn ngữ Việt/Anh cho toàn bộ giao diện
- ⭐ Trước đây ~120 câu (màn chi tiết phiên/kiện, tạo phiên, báo hư hỏng, END CODE, THIẾU MÃ KHO, thông báo lỗi API, trạng thái kiện…) viết thẳng tiếng Việt nên đổi sang English không đổi. Nay mọi chữ hiển thị đều qua `tr("…")` (`APIClient`, `AutoScanView`, `AutoScanViewModel`, `SessionsView`, `SettingsView`), câu có số/tên dùng `{0}`, `{1}`.
- `Localization.swift` (`L10n.en`): thêm 113 bản dịch, xoá 60 câu cũ không còn dùng (server cũ, quét QR END CODE, kết thúc phiên…). Hiện 163 câu, đã kiểm tra: không trùng khoá, mọi `tr("…")` trong code đều có bản dịch.
- Đổi ngôn ngữ ở ⚙️ → Ngôn ngữ / Language, hoặc nút VI | EN ở màn đăng nhập. Chữ do công ty trả về (tên hãng, tên mặt hàng, thông báo lỗi của máy chủ) không dịch.
- 🔥 Chưa làm: quyền camera/ảnh trong `Info.plist` (vẫn tiếng Việt, cần `InfoPlist.strings` + sửa project); `AppStore.buildTag` giữ tiếng Việt. Khi thêm chữ mới: viết `tr("câu tiếng Việt")` rồi thêm một dòng vào `L10n.en`.
- Chưa build Xcode. Thử: Cài đặt → English, duyệt các màn (phiên, kiện, tạo phiên, quét, báo hư hỏng).

### 2026-10-26 · ⭐ 📱 DOFA168 bị OCR đọc sai số 8 → nhầm sang FADO.VN
- ⭐ Kiện `300470092728` ghi mã kho `SG HUE DOFA16&.` (đúng ra là `SG HUE_DOFA168`, nhóm FADO 168). Chữ "168" bị đọc sai và dòng bắt đầu bằng "SG HUE DOFA" nên rơi vào quy tắc FADO.VN (kinh doanh).
- `RuleMatcher.normalizeOCR`: dòng bắt đầu `SG HUE` / `SG FRAGILE` + `DOFA` + `16…` (bất kỳ ký tự nào sau "16", có/không dấu cách hoặc `_`) → chuẩn hoá thành `SG HUE_DOFA168` / `SG FRAGILE_DOFA168`. Dòng `SG HUE DOFA` không có "16" vẫn là FADO.VN. Đã thử 8 chuỗi mẫu.
- 🔥 Kiện đã tạo với mã kho sai thì app không sửa được (công ty không cho đổi mã khách sau khi tạo); xử lý trên web (tab "Sửa mã" / "Xử lý kiện"). Chưa xác nhận phần "tracking nhận sai" của kiện này (cần ảnh tem). File: `RuleMatcher.swift`. Chưa build Xcode.

### 2026-10-26 · 🔥 📱 Sửa lỗi 401 khi quét (làm mới token chạy chồng nhau)
- 🔥 Nguyên nhân khả dĩ: khi token hết hạn, nhiều lệnh chạy song song (hỏi song song các mã ứng viên) cùng nhận 401 và **cùng đi làm mới token**. `refreshToken` chỉ dùng được một lần nên lần làm mới thứ hai bị từ chối → mất đăng nhập → lỗi 401 mọi lệnh sau.
- ⭐ `CompanyAPI.refreshOnce`: chỉ một lần làm mới tại một thời điểm, các lệnh khác chờ kết quả rồi gọi lại. Làm mới thất bại (400/401/403) thì xoá token, báo `CompanyAPI.sessionExpired`, `AuthStore` về màn đăng nhập với thông báo "Hết phiên đăng nhập — vui lòng đăng nhập lại".
- Cách xử lý tức thì khi gặp 401: ⚙️ → Đăng xuất → đăng nhập lại. Có thể 401 còn do đăng nhập cùng tài khoản ở nơi khác (web/iPhone khác) làm token cũ bị thu hồi — chưa xác nhận.
- File: `APIClient.swift`, `AuthStore.swift`. Chưa build Xcode.

### 2026-10-26 · 📱 Khớp mã kho khi OCR dính chữ phía trước + dòng OCR để gỡ lỗi
- ⭐ `RuleMatcher`: bỏ tiền tố có cả tên hãng ("USPS DELIVER TO:", "FEDEX SHIP TO"…); nếu dòng vẫn không khớp thì thử bỏ dần tối đa 4 từ đầu dòng ("XYZ ABC FDVAT HUE" → "FDVAT HUE"). Mã kho gửi công ty là phần đã cắt sạch.
- 🧪 Màn quét hiện 1 dòng chữ nhỏ **"OCR: …"** (tối đa 6 dòng chữ app đang đọc) để biết app đọc ra gì khi không ra mã kho. Chỉ để test, sẽ bỏ khi ổn định (`AutoScanViewModel.ocrDebug`, `AutoScanView.swift`).
- Ghi nhận: gợi ý "Chưa thấy mã vạch — đưa mã vạch vào khung" chỉ hiện khi mã kho ĐÃ đọc được mà mã vạch chưa đọc được, nên khi thấy gợi ý đó thì mã kho không phải vấn đề.
- File: `RuleMatcher.swift`, `AutoScanViewModel.swift`, `AutoScanView.swift`. Chưa build Xcode.

### 2026-10-26 · 📱 Quét nhanh không kịp đọc mã kho: chờ lâu hơn + cảnh báo THIẾU MÃ KHO
- ⭐ Cửa sổ chờ mã kho 1,0 → **2,5 giây**; mã kho vừa đọc được giữ **3 giây** (trước 1 giây) để tem kế tiếp dùng lại. Thời gian gom thêm tracking cùng tem giảm 0,7 → 0,5 giây nên tracking có đủ thông tin vẫn gửi nhanh.
- ⭐ Hết giờ mà chưa có mã kho (tem mới): lần 1 hiện thẻ cam **THIẾU MÃ KHO**, rung + âm báo, **chưa gửi** lên công ty; đưa tem vào lại. Lần 2 (trong 60 giây) gửi không kèm mã kho để không bị kẹt. Tracking thứ 2, 3 của cùng tem vẫn dùng mã kho của tem đó.
- Tem cũ rời khung mà chưa có mã kho thì chốt ngay khi tem mới vào (không bắt tem mới chờ hết 2,5 giây).
- Thẻ TING hiện thêm "Công ty không có mã này. Đã thử: …" (các mã ứng viên đã hỏi công ty) để biết vì sao không ra SUCCESS xanh.
- ⭐ `RuleMatcher.normalizeOCR` bỏ tiền tố "SHIP TO" / "DELIVER TO" / "TO" trước mã kho: tem USPS ghi `SHIP TO  SGHUE DOFA`, quy tắc FADO.VN neo đầu dòng nên trước đây không khớp nếu OCR đọc cả "SHIP TO" vào dòng. Chuỗi gửi công ty là mã kho đã bỏ tiền tố ("SGHUE DOFA"). 🔥 Chưa chắc đây là nguyên nhân duy nhất (chưa xem được dòng OCR thật trên iPhone).
- 🔥 `window` 2,5 giây làm vòng tiến trình chạy lâu hơn. Nếu thấy chậm, chỉnh `window` trong `AutoScanViewModel.swift`. File: `AutoScanViewModel.swift`, `AutoScanView.swift`, `RuleMatcher.swift`. Chưa build Xcode.

### 2026-10-26 · ⭐ 📱 Bỏ toàn bộ phần web cũ, app chỉ dùng hệ thống công ty
- ⭐ App không còn nói chuyện với server cũ (`http://...:3000`). Chỉ còn API công ty (`apiwh-dev.tinashipping.com/api`).
- **Đăng nhập thật:** `AuthStore` gọi `CompanyAPI.login` (POST `/auth/login`), token lưu Keychain, mật khẩu không lưu. `LoginView` bỏ chữ "bản thử". Hết hạn đăng nhập (401) khi tải danh sách phiên → tự về màn đăng nhập.
- **Đã xoá file:** `NewSessionView.swift`, `SessionDetailView.swift`, `PhotoOutbox.swift`. **Đã xoá code:** struct `APIClient` (server cũ) và các model cũ trong `Models.swift` (`ListResponse`, `ScanData`, `SessionItem`, `APIError`…), `CompanyAPI.readOnlyReport`.
- `SessionsView`: bỏ mục "Phiên đang mở trên web", nút + giờ tạo phiên trên công ty. `SettingsView`: bỏ ô địa chỉ server, bỏ form đăng nhập công ty trong Cài đặt (đăng nhập ở màn đầu), bỏ công tắc "Tự chụp ảnh label"; còn tài khoản + đăng xuất, ngôn ngữ, bản app, quy tắc mã kho. `AppStore`: chỉ còn quy tắc mã kho cài sẵn.
- `AutoScanViewModel` / `AutoScanView`: bắt buộc có `CompanyScanTarget`; bỏ đường gửi server cũ, báo hỏng bằng ảnh đơn giản cũ, hàng đợi ảnh, tự chụp ảnh, đồng bộ số đếm 1 giây, nút "Kết thúc phiên" (đóng phiên công ty không làm từ app). Menu ⋯ chỉ còn "Dừng quét" (dừng trên máy, không đổi gì trên công ty).
- 🔥 Chưa làm: bỏ `NSAllowsArbitraryLoads` và `NSLocalNetworkUsageDescription` trong `project.yml` / `Info.plist` (không còn cần cho server nội bộ). Chưa build Xcode: cần Run và thử đăng nhập → danh sách phiên → quét → END CODE → báo hỏng.

### 2026-10-26 · 📱 Báo hư hỏng của kiện trên điện thoại (phiên công ty, GHI thật)
- ⭐ Ở màn quét phiên công ty, nút "Hỏng" (sau khi kiện vừa ghi) mở bảng **Báo hư hỏng** giống web: 1) Loại hư hỏng (lưới 2 cột, chọn nhiều; danh sách lấy từ `GET /damage-types`) → 2) Ảnh hư hỏng (chụp, tối đa 10, xoá được từng ảnh) → 3) **Quyết định ở cuối cùng** (Nhận hàng / Từ chối) → nút "Gửi báo cáo" (cần chọn ≥1 loại, có hộp xác nhận).
- Gửi bằng `POST /trackings/{id}/damage-report` (multipart: `damageTypeCodes` lặp từng mã, `decision` RECEIVED|REJECTED, `files`). Mỗi kiện chỉ 1 báo cáo (gửi lần hai: 409, app hiện lỗi). Từ chối → công ty chuyển kiện sang trả người bán; kiện đã vào thùng công ty không cho từ chối.
- `APIClient.swift`: `CompanyPart`, `CompanyDamageType`, `CompanyAPI.damageTypes()`, `reportDamage(...)`; `request(...)` hỗ trợ multipart nhiều phần (ảnh label đổi theo). `AutoScanView.swift`: thêm `CompanyDamageSheet`. Phiên server cũ giữ nguyên cách báo ảnh hỏng cũ.
- 🔥 Cách gửi nhiều mã loại hư hỏng đoán theo tài liệu (chưa thử thật). Công ty có `DELETE /trackings/{id}` (xoá mềm kiện quét nhầm, bắt buộc lý do) — chưa dùng. Chưa build Xcode.

### 2026-10-26 · 📱 Nút END CODE trên màn quét (thay cho quét mã END CODE)
- ⭐ Khi có ≥1 tracking chưa có thông tin ("TING"), màn quét hiện nút to **END CODE** phía trên thanh nút dưới (`AutoScanView`); bấm 1 lần = gửi `ENDCODE` (`AutoScanViewModel.endCode()`, chống bấm đúp 1,5 giây, không hỏi xác nhận). Đủ 3/3 thì nút đỏ "Bắt buộc bấm để chốt". Áp dụng cho cả phiên công ty và phiên server cũ.
- Cảnh báo chặn (đủ 3 tracking mà quét tiếp) đổi từ pop-up che kín màn hình sang khung đỏ ở phía trên, không che nút; chữ "quét QR END CODE" đổi thành "bấm nút END CODE".
- Quét mã `ENDCODE` bằng camera vẫn dùng được (giữ làm dự phòng).
- File: `AutoScanView.swift`, `AutoScanViewModel.swift`, `WarehouseScanner-iOS/README.md`. Chưa build Xcode.

### 2026-10-26 · 📱 Quy tắc mã kho cài sẵn trong app + quét công ty nhanh hơn
- ⭐🔥 App không còn tải quy tắc mã kho từ server cũ và không dùng bản lưu `cachedRules` nữa: 4 quy tắc cài cố định trong `AppStore.swift` (`WarehouseRule.builtIn`: Giaonhan247, FADO 168, MICAFI, FADO.VN; chép từ `schema.sql` mặc định + bản sửa `FD ?VAT ?HUE`). Bạn đã xác nhận đúng. **Muốn đổi quy tắc: sửa danh sách này rồi build lại app** (sửa trên web cũ không còn ảnh hưởng app).
- `AppStore.refresh()` chỉ kiểm tra kết nối server cũ (cho phiên server riêng); dòng thông báo ghi số quy tắc cài sẵn.
- ⭐ Quét công ty: hỏi `check-tracking-scan` **song song** tất cả mã ứng viên (trước đó hỏi lần lượt nên chậm), chọn mã đứng trước trong danh sách (`AutoScanViewModel.sendCompany`).
- File: `AppStore.swift`, `AutoScanViewModel.swift`, `WarehouseScanner-iOS/README.md`, `warehouse-receiving/README.md`. Chưa build Xcode.

### 2026-10-26 · 📱 Quét công ty theo rule Phần 1 + cắt chuỗi tracking + bỏ FAIL + bỏ tự chụp ảnh label
- ⭐ Sửa lỗi: kiện có thông tin ở tracking 2 hoặc 3 giờ gửi kèm các tracking "ting" trước đó làm mã phụ (`additionalTrackingNumbers`), trước đây bị bỏ mất.
- ⭐ Cắt chuỗi: `TrackingCutter` (APIClient.swift) chép từ `server/utils/trackingFormats.js` + bộ định dạng mặc định trong `schema.sql` (USPS 420+ZIP, 9…, UPS 1Z, FedEx 30–34 số/96/92, DHL, Amazon TBA) và ZIP+4. Mỗi mã vạch sinh các mã ứng viên (mã gốc trước), app hỏi công ty lần lượt, gặp FOUND/DUPLICATE thì dừng. Mã đã cắt là mã gửi đi / làm tracking gốc. 🔥 Bảng định dạng trong app là bản cố định, sửa bảng `tracking_formats` trên server không đổi app.
- ⭐ Bỏ FAIL: không báo FAIL lên server nữa (`reportFail` chỉ nhắc "Chưa thấy mã vạch"), bỏ ô đếm FAIL ở màn quét. Lỗi gửi công ty hiện ở thẻ BỎ QUA kèm thông báo.
- ⭐ Bỏ tự chụp ảnh label: công tắc "Tự chụp ảnh label khi quét" mặc định TẮT (`AutoScanViewModel`, `SettingsView`). Ảnh label chụp chủ động bằng nút "Ảnh label"; ở phiên công ty ảnh gửi bằng `POST /trackings/{id}/label-photos` (multipart, `CompanyAPI.uploadLabelPhoto`). Ảnh hỏng chưa hỗ trợ ở phiên công ty.
- Thẻ kết quả riêng cho phiên công ty (SUCCESS + mã kho + MATCHED/NO_NAME). `CompanyAPI.scan` trả thêm `id` kiện.
- Block (Phần 2) làm trên web công ty; app chưa xử lý riêng. NO NAME có thẻ riêng + gợi ý chụp ảnh label. Nhóm chờ lưu khi tắt app: chưa làm theo yêu cầu. Chưa build Xcode.
- File: `APIClient.swift`, `AutoScanViewModel.swift`, `AutoScanView.swift`, `SettingsView.swift`, `WarehouseScanner-iOS/README.md`.

### 2026-10-26 · 📱 Quét vào phiên công ty (GHI thật lên apiwh-dev) — bước 4b
- Màn "Phiên #…" của phiên công ty đang mở có thêm dòng "Quét vào phiên này (ghi lên công ty)" → mở màn quét ở chế độ công ty. Quét bằng nút này là kiện THẬT, không xoá được. Màn quét cũ (phiên server riêng) giữ nguyên.
- Quy trình mỗi mã: `check-tracking-scan` → FOUND: ghi ngay `POST /trackings/scan` (kiện có thông tin) · NOT_FOUND: "ting", chờ tracking tiếp theo (đủ 3 thì bắt buộc `ENDCODE`) · `ENDCODE`: ghi tracking đầu thành kiện NO NAME, các mã còn lại là mã phụ · DUPLICATE: báo đã quét. Mất mạng thì tự gửi lại (lệnh quét an toàn khi gửi lại, công ty trả DUPLICATE).
- Mã kho đọc được gửi vào `customerCode`. Ghi chú mỗi dòng lịch sử hiện MATCHED/NO_NAME và mã kho gửi đi để đối chiếu với web.
- `APIClient.swift`: `CompanyScanTarget`, `CompanyAPI.scan(...)`. `AutoScanViewModel.swift`: thêm `company`, `sendCompany(...)`, nhóm chờ `coPending` (chỉ trong bộ nhớ, tắt app là mất). `AutoScanView.swift`: tham số `company`; ở chế độ công ty không gọi server cũ (không đồng bộ số đếm, "Dừng quét" chỉ dừng trên máy, "Kết thúc phiên" chỉ thoát màn hình, không đóng phiên công ty). `SessionsView.swift`: dòng vào màn quét.
- ⭐🔥 Chưa làm: cắt chuỗi tracking, ảnh label, báo FAIL lên công ty, lưu nhóm chờ khi tắt app. Chưa kiểm chứng `customerCode` nên gửi mã kho đọc được từ nhãn. Chưa build Xcode.

### 2026-10-26 · 📱 Tạo phiên thử trên công ty (GHI lên apiwh-dev)
- Màn Phiên: nút "Tạo phiên thử trên công ty (ghi)" mở form: hãng (phải chọn), cửa kho, người giao, số kiện hãng khai. **Không có giá trị mặc định**, tất cả tự nhập; nút chỉ bấm được khi đã chọn hãng, nhập người giao và số kiện là số.
- Có hộp xác nhận trước khi gửi. Nút khoá khi đang gửi và sau khi tạo xong (tránh tạo trùng). Trạm lấy từ `/auth/me` (trạm đầu tiên).
- `APIClient.swift`: `CompanyJSON.intValue`, `CompanyAPI.createSession(...)` = `POST /receiving-sessions`; chỉ đọc `id` từ phản hồi (không giải mã cả phiên, để lỗi giải mã không khiến bấm tạo lần nữa). `SessionsView.swift`: thêm `CompanyNewSessionView` và nút/sheet.
- ⭐🔥 Đây là lệnh GHI thật, phiên không xoá được. Chỉ tạo một phiên thử. Phiên chỉ có trên hệ thống công ty, không có trên web cũ của mình. Chưa build Xcode.

### 2026-10-26 · 📱 Kiểm tra mã với công ty (bước 4a, không ghi)
- Trong màn "Phiên #…" có mục "Kiểm tra mã với công ty": gõ/dán mã → hiện FOUND / NOT_FOUND / DUPLICATE và nguyên văn dữ liệu công ty trả về.
- `APIClient.swift`: thêm `CompanyJSON` (đọc JSON bất kỳ) và `CompanyAPI.checkTracking(code:)` = `POST /trackings/check-tracking-scan`. `SessionsView.swift`: thêm mục kiểm tra trong `CompanyTrackingsView`.
- ⭐ Lệnh là POST nhưng theo tên/tài liệu chỉ kiểm tra, không tạo kiện. 🔥 Chưa kiểm chứng: lần thử đầu xem phiên trên web có thêm kiện không. Chưa build Xcode.

### 2026-10-26 · 📱 Phiên công ty: xem danh sách kiện và chi tiết kiện (chỉ đọc)
- Chạm một phiên công ty → màn "Phiên #…": nút "Chọn dùng phiên này", đã quét / hãng khai, danh sách kiện (tracking, trạng thái, khách, kệ, giờ check-in, nhãn NO NAME), tải 30 kiện mỗi lần, cuộn xuống tải tiếp, kéo để làm mới.
- Chạm một kiện → "Chi tiết kiện": mã phụ, trạng thái, khớp đơn, tình trạng, số lượng, hàng trong kiện, hàng giữ, số ảnh label.
- `APIClient.swift`: thêm model kiện (đọc "dễ tính", trường thiếu/lệch kiểu không làm hỏng cả danh sách), `CompanyAPI.trackings(sessionId:page:limit:)` = `GET /trackings?receivingSessionId=`, `CompanyAPI.tracking(id:)` = `GET /trackings/{id}`.
- `SessionsView.swift`: dòng phiên công ty thành `NavigationLink`; thêm `CompanyTrackingsView`, `CompanyTrackingDetailView` (không thêm file mới).
- ⭐ Chỉ GET, không ghi gì lên công ty. 🔥 Tên trường lấy từ OpenAPI, chưa thử với dữ liệu thật: ô nào hiện "—" thì báo để chỉnh. Chưa build Xcode.

### 2026-10-26 · 📱 Phiên công ty: hiện tên hãng thay cho "hãng 5 / hãng 6"
- Lỗi hiển thị: danh sách phiên của API chỉ trả `carrierId` (không kèm tên hãng, trạm, người mở) nên app hiện "hãng 5", "hãng 6". `SessionsView.swift`: gọi `GET /carriers` một lần rồi tra id → tên (`coCarrierName`); API có trả kèm tên thì ưu tiên tên đó; không tra được thì vẫn hiện "hãng N". Lỗi tải danh sách hãng không làm hỏng danh sách phiên.
- Dòng phụ "trạm / mở bởi" chưa hiện vì API không kèm các trường đó trong danh sách (cần tham số `include`, chưa kiểm tra giá trị hợp lệ).
- Chỉ đọc, không ghi gì lên công ty. 🧪 Chưa build/thử.

### 2026-10-26 · 📱 Phiên công ty hiển thị đủ thông tin như web (chỉ đọc)
- `APIClient.swift`: `CompanySession` đọc thêm `carrierReportedCount`, `licensePlate`, `vehicleType`, `vehicleArrivedAt`, `user` (`CompanyUserRef`).
- `SessionsView.swift`: mỗi phiên công ty hiện **đã quét / hãng khai** (vd 6 / 20) thay vì chỉ số đã quét; dòng chi tiết thêm biển số, loại xe; dòng phụ: trạm · giờ xe đến (giờ máy, dd/MM HH:mm) · người mở phiên.
- Chưa có màn hình **danh sách kiện trong phiên** (như bảng kiện trên web) — cần xác nhận endpoint API trước. Không ghi gì lên công ty. 🧪 Chưa build/thử.

### 2026-10-26 · ⭐📱 Nối API công ty — bước 3 (chỉ đọc): hiện phiên công ty đang mở + chọn phiên
- `SessionsView.swift`: thêm mục **"Phiên công ty đang mở (thử, chỉ đọc)"** ở đầu màn hình Phiên nhận hàng, lấy từ `GET /receiving-sessions?status=OPEN` (mới nhất trước): mã phiên, hãng, cửa, người giao, trạm, số đã quét. Chạm một phiên để **chọn**; phiên chọn chỉ lưu trên máy (`company.selectedSessionId`, `company.selectedSessionLabel`), **chưa ghi gì lên công ty**.
- Chưa đăng nhập công ty thì mục này nhắc vào Cài đặt; lỗi của server cũ và lỗi của API công ty hiển thị riêng, không ảnh hưởng nhau. Danh sách phiên cũ (server của bạn) giữ nguyên bên dưới. Làm mới khi kéo xuống, bấm ↻ hoặc đóng Cài đặt.
- 🧪 Chưa build/thử (kiểm cú pháp bằng trình phân tích). Không tạo file `_old`; hoàn tác bằng `git show HEAD:<file> > <file>`.

### 2026-10-26 · ⭐🔥📱 Nối API công ty — bước 1–2: đăng nhập + lần chạy chỉ đọc (chưa ghi gì lên công ty)
- Phương án A: app gọi thẳng API công ty (`apiwh-dev`). Chi tiết, trạng thái từng bước và kiến thức API: xem **`API_INTEGRATION.md`** (file mới).
- `APIClient.swift` (thêm cuối file): `KeychainStore` (token lưu Keychain, không lưu mật khẩu), `actor CompanyAPI` — `POST /auth/login`, tự làm mới token khi 401 (refreshToken dùng một lần, tránh làm mới chồng nhau), `GET /auth/me`, `/carriers`, `/customer-code-mappings`, `/receiving-sessions?status=OPEN`; `readOnlyReport()` trả đoạn chữ hiển thị.
- `SettingsView.swift`: mục "Kết nối công ty (thử, chỉ đọc)": ô tên đăng nhập, mật khẩu, nút Đăng nhập, Kiểm tra chỉ đọc, Đăng xuất công ty.
- ⚠️ Chưa có lệnh ghi (tạo phiên, quét kiện). Đăng nhập vào app, quét, server, web giữ nguyên. Chỉ dùng tài khoản thử; sai mật khẩu nhiều lần có thể bị khoá tạm thời.
- 🧪 Chưa build/thử: sandbox không có trình biên dịch Swift (chỉ kiểm cú pháp bằng trình phân tích). Cần build trong Xcode, nếu lỗi gửi lại nội dung lỗi. Không tạo file `_old`; hoàn tác bằng git.
- 🔧 Sửa lỗi biên dịch lần build đầu: Xcode báo `Type 'Err' cannot be nested in generic function 'request'` → chuyển struct đọc lỗi ra ngoài thành `CompanyErrorBody` (`APIClient.swift`). Kết quả thử trên máy thật 26/10: đăng nhập công ty + kiểm tra chỉ đọc chạy tốt (tài khoản `nhanvientram`, trạm OR_1 id 1, 10 hãng, 12 phiên đang mở).
