# NHẬT KÝ THAY ĐỔI — App iPhone quét kho (WarehouseScanner-iOS)

> Nhật ký riêng của app iOS, tách từ `warehouse-receiving/CHANGELOG.md` ngày 26/10/2026 khi tách thư mục iOS và web.
> **Quy tắc:** mỗi khi sửa code app, thêm một mục mới ở đầu phần "Lịch sử" (mới nhất ở trên). Lịch sử cũ (trước 26/10/2026) và phần server/web vẫn ở `warehouse-receiving/CHANGELOG.md`.

**Ký hiệu:** ⭐ quan trọng · 🔥 khó / dễ sai · 🧪 chỉ để test · 📱 cần build lại app trong Xcode

---

## Lịch sử thay đổi (mới nhất ở trên)

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
