# NHẬT KÝ NỐI API CÔNG TY — App quét kho ↔ `apiwh-dev`

> Chép sang thư mục iOS ngày 26/10/2026. Đường dẫn file trong tài liệu này tính từ thư mục `WarehouseScanner-iOS`.


> File này ghi lại **việc đang làm khi nối app iPhone với API công ty**: mục tiêu, trạng thái từng bước, kiến thức về API, việc còn nghi vấn.
> Mỗi lần làm thêm một bước, cập nhật file này **và** `CHANGELOG.md`. **Không ghi mật khẩu hay token vào file này.**

Cập nhật lần cuối: 26/10/2026

**Kết quả thử 26/10/2026:** đăng nhập công ty và kiểm tra chỉ đọc chạy tốt: tài khoản `nhanvientram` (Nhan vien 01), trạm OR_1 (id 1), 10 hãng (Amazon Logistics / Package / Pallet là 3 hãng riêng), bảng mã khách chỉ có 1 dòng thử `ZZ-FE-PROBE-20261020` (chưa có hub) nên chưa xác định được `customerCode`; 12 phiên đang mở.

## 1. Mục tiêu và phương án
- **Phương án A (đã chọn):** app iPhone gọi thẳng API công ty. Server, web, database của mình giữ lại làm môi trường thử và dự phòng.
- Giữ trong app (API công ty không có): camera + OCR, quy tắc mã kho, cắt chuỗi tracking, END CODE (`ENDCODE`), hàng chờ nhóm mã, trạng thái FAIL.
- Địa chỉ API thử: `https://apiwh-dev.tinashipping.com/api` (tài liệu: `/api/docs`). Web công ty thử: `https://warehouse-dev.tinashipping.com`.
- Quy tắc an toàn: chỉ dùng `apiwh-dev` với **tài khoản thử**; Claude không nhập mật khẩu/token thay bạn; chưa ghi gì lên hệ thống công ty.

## 2. Trạng thái các bước

| Bước | Nội dung | Trạng thái |
|---|---|---|
| 0 | Xin tài khoản thử, xác nhận mạng (4G mở được Swagger → không cần VPN) | Xong. Còn chờ trả lời: `customerCode`, xoá kiện nhầm, chia Amazon |
| 1 | Đọc tài liệu OpenAPI | Xong (ghi ở mục 3) |
| 2 | Đăng nhập công ty + token Keychain + làm mới token + lần chạy chỉ đọc (Cài đặt → "Kết nối công ty") | **Đã chép về máy 26/10/2026, chờ build + thử trên Xcode** |
| 3 | Chọn phiên công ty và xem danh sách kiện + chi tiết kiện (chỉ đọc) đã làm 26/10/2026, chờ build + thử. **Tạo phiên mới** (ghi lên công ty) chưa làm, cần bạn đồng ý | Một phần |
| 4 | Quét: cắt chuỗi, `check-tracking-scan`, `trackings/scan`, nhóm mã | 4a (kiểm tra mã, không ghi) đã chép 26/10/2026, chờ build + thử. Tạo phiên thử (ghi) đã chép 26/10/2026, chờ build + thử. 4b (quét `trackings/scan`) đã chép 26/10/2026, chờ build + thử 1 kiện trên phiên #16. Đã thêm cắt chuỗi, ảnh label (chủ động), bỏ FAIL; chưa làm lưu nhóm chờ khi tắt app |
| 5 | NO NAME, `ENDCODE`, hàng chờ lưu trên máy | Chưa làm |
| 6 | Gửi ảnh nhãn (`label-photos`) | Chưa làm |
| 7 | Thử thực tế trên `apiwh-dev`, sau đó chạy thử với vài người | Chưa làm |

## 3. Kiến thức về API (đọc từ OpenAPI, chưa gọi bằng tài khoản)
- Phản hồi thành công: `{ success, statusCode, message, data, meta? }`. Lỗi: `{ success:false, statusCode, code, message, errors[] }`.
- `POST /auth/login` body `{ username, password }` → `data { accessToken, refreshToken }`. Sai thông tin → 401 `UNAUTHORIZED`; **sai nhiều lần có thể bị khoá tạm thời**. `username` bị đổi thành chữ thường khi so khớp.
- `POST /auth/refresh` body `{ refreshToken }` → cặp token mới (refreshToken dùng một lần). `POST /auth/logout` body `{ refreshToken }`.
- `GET /auth/me` → `id, username, fullName, systemRole, stations[{id, code, name}]`.
- `GET /carriers` (page, limit, search, isActive) → `{ id, code, name, isActive }`. `carrierId` là số nguyên.
- `GET /customer-code-mappings` (page, limit, customerCode) → `{ id, customerCode, destinationHubId, version, effectiveFrom }`.
- `GET /receiving-sessions` (page, limit, carrierId, stationId, status OPEN|CLOSED, dockGate, openedFrom/To, closedFrom/To, include).
- `POST /receiving-sessions` — **bắt buộc:** `stationId`, `carrierId`, `driverName`, `carrierReportedCount`. Tuỳ chọn: `licensePlate`, `vehicleType`, `dockGate`, `vehicleArrivedAt`.
- `PATCH /receiving-sessions/{id}` — đổi `status` (OPEN/CLOSED), `vehicleDepartedAt`, thông tin xe.
- `POST /trackings/check-tracking-scan` body `{ code }` → `data.status` FOUND | NOT_FOUND | DUPLICATE (+ `orderItems`).
- `POST /trackings/scan` body `{ trackingNumber, additionalTrackingNumbers[], carrierId, customerCode, binLocationId, receivingSessionId }` → `data { id, matchStatus MATCHED|NO_NAME, checkInResult CREATED|DUPLICATE, status, destinationHubId, ... }`. Gửi lại cùng mã thì ra `DUPLICATE`.
- `POST /trackings/{id}/label-photos` (multipart, trường `files`) → 201.
- Web công ty (phiên 5, đã đóng): bảng kiện có Tracking (+mã phụ), Status (CHECKED_IN, CHECKED_OUT, CONSOLIDATED, ON_HOLD), Khách, Destination Hub / Box, Người quét, Vị trí kệ, Check-in, Thực nhận/Khai báo.

## 4. Việc còn nghi vấn (cần xác nhận trước khi code tiếp)
1. **`customerCode` là gì?** Cột "Khách" trên web hiển thị mã kiểu `UIO166` → có vẻ là mã khách, chưa chắc là mã kho in trên nhãn. Xem kết quả nút "Kiểm tra chỉ đọc" trong app.
2. **Xoá kiện quét nhầm** trên môi trường thử bằng cách nào / ai có quyền? (chưa hỏi manager)
3. **Chia Amazon Logistics / Package / Pallet**: quy tắc của kho là gì? (chưa có thông tin) `TBA`/`TBC`/`TBM` đều là tiền tố mã Amazon Logistics.
4. API không có END CODE / hàng chờ → app phải lưu nhóm đang chờ trên máy để không mất khi tắt app.
5. API so khớp theo mã đã cắt sẵn → luật cắt chuỗi phải chép vào app (xem `server/utils/trackingFormats.js`).

## 5. File đã sửa (nối API)
- `WarehouseScanner-iOS/WarehouseScanner/APIClient.swift` — thêm cuối file: `KeychainStore`, `CompanyError`, các model `Company*`, `actor CompanyAPI` (đăng nhập, làm mới token, 6 lệnh chỉ đọc gồm `trackings`/`tracking`, `checkTracking`, `createSession` (ghi), `scan` (ghi), `readOnlyReport()`). Phần API cũ giữ nguyên.
- `WarehouseScanner-iOS/WarehouseScanner/SettingsView.swift` — thêm mục "Kết nối công ty (thử, chỉ đọc)".
- `WarehouseScanner-iOS/WarehouseScanner/SessionsView.swift` — thêm mục "Phiên công ty đang mở" (chọn phiên, chỉ ghi nhớ trên máy) và 2 màn xem kiện / chi tiết kiện (`CompanyTrackingsView`, `CompanyTrackingDetailView`) kèm mục "Kiểm tra mã với công ty" và `CompanyNewSessionView` (tạo phiên thử, ghi lên công ty).
- Không thêm file Swift mới (tránh phải thêm vào Xcode). Hoàn tác: `git checkout -- <file>` (nếu git báo không xoá được file thì dùng `git show HEAD:<file> > <file>`).

## 6. Cách thử bước 2 (trên iPhone)
1. Build lại app trong Xcode.
2. Mở Cài đặt → mục "Kết nối công ty" → nhập tên đăng nhập + mật khẩu **tài khoản thử** → "Đăng nhập công ty".
3. Bấm "Kiểm tra chỉ đọc". Kết quả hiện: tài khoản, trạm, hãng (id), mã khách → hub, phiên đang mở.
4. Chụp màn hình (mật khẩu không hiển thị; app không hiện token) gửi lại để chọn bước tiếp.

## 7. Kết quả thử ngày 26/10/2026
- Xem kiện / chi tiết kiện (phiên #15) khớp với web công ty.
- `customerCode` = mã kho Việt Nam (bạn xác nhận). Công ty không có cách xoá kiện hoặc phiên: mọi lần ghi là vĩnh viễn. Amazon chưa hỏi được.
- `check-tracking-scan`: mã đã có trả DUPLICATE kèm phiên đã quét (`receivingSessionId`), đơn khớp, người quét; mã chưa có trả NOT_FOUND. Đã thử, chưa thấy tạo kiện thêm trên web.
- Rule quét dự kiến giữ nguyên (SUCCESS / NO NAME / FAIL, nhóm 3 mã, `ENDCODE`, cắt chuỗi, rule mã kho). Phần quét ghi lên công ty (4b) chưa làm.
- Phiên thử trên công ty: #16 (tạo trên web công ty). Quét thử bằng dòng "Quét vào phiên này (ghi lên công ty)".
- Rule Phần 1 (scan tracking), Phần 2 (Block), Phần 3 (NO NAME) do bạn cung cấp 26/10: app đã theo Phần 1 và Phần 3 (thẻ NO NAME + ảnh label chủ động); Phần 2 (Block) xử lý trên web công ty.
- Quy tắc mã kho đã cài sẵn trong app (không còn lấy từ server cũ); quét công ty hỏi các mã ứng viên song song.
- END CODE: bấm nút trên màn quét (không cần quét mã nữa).
- Báo hư hỏng: `POST /trackings/{id}/damage-report` (loại, ảnh, quyết định). Công ty còn `DELETE /trackings/{id}` (xoá mềm kiện quét nhầm, cần lý do; từ chối nếu kiện đã vào thùng/có đơn liên kết/đang giữ) — chưa dùng.
