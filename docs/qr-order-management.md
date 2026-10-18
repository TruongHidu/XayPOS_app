# Nhận và duyệt yêu cầu QR tại bàn — 18/10/2026

Trong **Gọi món → chọn bàn**, nút **Yêu cầu QR (n)** mở hàng đợi QR tại bàn. Thẻ bàn có nhãn xanh dương **QR · n yêu cầu mới**; số này đếm yêu cầu, không phải số món hoặc tổng số lượng. Màu bàn vẫn thể hiện đơn chưa xác nhận (vàng), đã xác nhận (xanh) hoặc còn trống. QR chưa duyệt không làm bàn bận và không cộng tiền vào bill.

Chạm nhãn trên một bàn để mở yêu cầu của bàn đó; nút đầu màn hình mở toàn bộ yêu cầu TABLE đang chờ. Mỗi yêu cầu có thời gian gửi, khách, ghi chú, tóm tắt món và giá lúc gửi. Mở chi tiết để xem đầy đủ món, giá hiện tại và ngữ cảnh lượt khách.

## Duyệt và từ chối

1. Mở chi tiết để app gọi GET mới; snapshot danh sách không dùng để duyệt.
2. Đối chiếu món, giá lúc gửi/giá hiện tại và bàn/phiên đang phục vụ. Nếu khách gửi lúc bàn chưa có phiên nhưng nay có phiên, phải xác nhận đúng lượt khách hiện tại.
3. Chọn ô xác nhận rồi **Duyệt yêu cầu**. Backend mở phiên/tạo đơn hoặc append vào đơn đủ điều kiện của đúng phiên. App chỉ gửi request version, review hash và session đã review, không gửi giá hoặc tự tạo order thay thế.
4. Từ chối bằng nút **Từ chối**, nhập lý do bắt buộc (trim, 1–1000 ký tự), rồi **Xác nhận từ chối**.
5. Thành công bỏ request khỏi danh sách chờ theo response backend và phát refresh để đơn/bàn đọc dữ liệu mới. Không đổi sourceChannel root thành QR_TABLE khi gọi thêm.

Không tự confirm đơn OPEN qua QR; backend trả reason và app khóa duyệt. Xử lý nháp bằng luồng nhân viên rồi tải lại review. Không gắn yêu cầu đã quan sát phiên cũ vào lượt khách khác. Nhãn bàn chỉ tính request có observedSessionId null hoặc khớp phiên hiện tại; inbox chung vẫn cho xem và xử lý request cần kiểm tra.

## API và quyền

API dùng authenticated Dio/staff session, JSON, Accept application/json và Cache-Control no-store. Không dùng public guest API/token, không cache bền vững và không thêm dependency.

| API | Request | Quyền |
| --- | --- | --- |
| GET /api/v1/qr-order-requests | entryType=TABLE, status=PENDING, includeExpired=false, page, size=100 | ORDER_VIEW + ORDER_MANAGEMENT |
| GET /api/v1/qr-order-requests/{id} | Không body | ORDER_VIEW + ORDER_MANAGEMENT |
| POST /api/v1/qr-order-requests/{id}/approve | expectedRequestVersion, expectedReviewContextHash, targetSessionId | ORDER_CREATE + ORDER_UPDATE; feature QR theo entry |
| POST /api/v1/qr-order-requests/{id}/reject | expectedRequestVersion, reason | ORDER_UPDATE + ORDER_MANAGEMENT |

Approve TABLE cần QR_MENU_VIEW, QR_TABLE_ORDER, ORDER_MANAGEMENT, TABLE_MANAGEMENT; thêm TABLE_OPEN khi mở phiên. Không suy quyền từ tên gói/role hoặc việc catalog có feature mới. App kiểm tra permissions/features hiệu lực và backend canApprove. List/detail/reject vẫn dùng được để xử lý backlog sau khi QR grant bị thu hồi nếu quyền vận hành ORDER_MANAGEMENT còn hiệu lực.

expectedRequestVersion là version của QR request. expectedReviewContextHash lấy nguyên từ GET review; app không tự tính hoặc thay hash để retry. targetSessionId luôn có trong JSON, kể cả null khi review chưa có phiên. Nhân viên xác nhận ngữ cảnh trước khi gửi. POST approve/reject không tự thêm Idempotency-Key; backend quản lý replay/đồng thời theo request ID và version/context.

## Đồng bộ và lỗi

Đọc đủ các trang vào snapshot rồi mới thay danh sách; gộp request ID trùng bằng version mới hơn. Không gọi API cho từng thẻ bàn. Đếm PENDING còn hạn; APPROVED/REJECTED/CANCELLED giữ trạng thái terminal kể cả expired=true. Chỉ báo yêu cầu mới với requestId chưa thấy sau lần tải đầu, không báo lại mỗi lần poll.

Polling 12 giây khi chọn bàn hoặc inbox đang hiện và app foreground. Dừng khi route khác che màn, vào review hoặc app background; trở lại tải mới. Lỗi tăng khoảng đợi theo backoff; HTTP429 tôn trọng Retry-After. Có tải lại thủ công và báo khi đang giữ dữ liệu cũ do lỗi mạng.

Mở review không tự POST. Một lần quyết định khóa nhấn trùng; approve phối hợp OrderEvents và khóa phiên với chuyển bàn/thanh toán/gọi thêm. Response cũ sau logout/đổi tenant/quyền/feature không áp dụng vào scope mới. UI dùng OrderResponse/version backend, không tự dựng order.

Sau 409, tải lại đúng request, hiển thị ngữ cảnh/giá mới và bỏ ô xác nhận cũ; không tự duyệt tiếp. Timeout/5xx/response sai giữ trạng thái chưa xác định, chặn gửi lại/đóng review cho tới khi tải lại để đối chiếu. GET terminal giải quyết kết quả; GET vẫn PENDING cần kiểm tra/xác nhận lại. Không fallback tạo hoặc append bằng API staff.

## Cấu trúc

- `lib/features/qr_order/domain`: entity request/review/approval; MenuPrice/OrderQuantity hiện có; repository interface và use case phân trang/đọc/duyệt/từ chối.
- `data`: DTO kiểm schema/liên kết request/order/items, remote data source, repository chuyển lỗi thành Result/Failure và xử lý Retry-After.
- `presentation`: QrInboxController quản lý snapshot/polling; QrReviewController quản lý review/decision/recovery; Riverpod providers theo orderScope; dialog inbox/review và visibility theo route/lifecycle.
- Tích hợp tại AccessPolicy, app providers/router và OrderServiceContextScreen. Luồng widget → controller → use case → repository interface → repository impl → data source → Dio.

Phạm vi là nhận/duyệt QR TABLE trên app nhân viên. Chưa thêm UI QR mang đi, lịch sử request terminal, nhãn nguồn QR bền vững trên từng dòng order hoặc WebSocket/thông báo nền. Backend và web khách hàng giữ nguyên.

## Xác minh

Kiểm thử fake repository/Dio interceptor, không gọi dữ liệu nhà hàng thật: payload/version/hash/null session; phân trang; expiry/terminal; quyền/feature; xác nhận trước gửi; từ chối có lý do; khóa thao tác; conflict/timeout/scope; tiền chỉ đổi sau approve; polling theo route/lifecycle; responsive 320/800 px với chữ hệ thống 200%/bàn phím và ảnh đối chiếu màu bàn.

Kết quả ngày 18/10/2026:

- `dart analyze`: **No issues found**.
- `flutter test --no-pub --reporter expanded`: **545/545 test đạt**, 88 giây; gồm **22 test QR mới** (14 domain/data/controller, 8 widget/tích hợp/golden).
- Golden chọn bàn cũ cập nhật cho nút inbox mới; golden QR mới đối chiếu màu bàn đã xác nhận/chưa xác nhận/trống cùng nhãn QR. Không đổi golden các module khác.
- `git diff --check`: đạt. Không thêm dependency; không thay đổi backend hoặc web khách hàng.
- Chưa build APK hoặc kiểm chứng với thiết bị/backend thật.
