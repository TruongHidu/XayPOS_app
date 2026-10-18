# Thanh toán, thao tác món và hoàn tất đơn

Mở **Gọi món → chọn bàn → chi tiết đơn** hoặc **Đơn hàng → chi tiết**. Thanh cuối có Tạm tính và nút Thanh toán hóa đơn. Khi backend xác nhận PAID, giao diện chuyển sang Hoàn tất đơn. Nếu còn món chưa SERVED, người có thêm ORDER_MARK_SERVED có thể xác nhận phục vụ tất cả rồi hoàn tất. COMPLETED hiển thị Đã hoàn tất; CANCELLED không có thao tác thanh toán/hoàn tất.

## Quy trình sử dụng

1. Chọn Thanh toán hóa đơn, kiểm tra mã đơn và tổng tiền từ backend.
2. Chọn Tiền mặt hoặc Chuyển khoản; chuyển khoản phải có mã tham chiếu giao dịch đã đối soát thủ công.
3. Xác nhận đã nhận đủ tiền rồi gửi. Hiện backend chỉ nhận thanh toán đủ một lần, amount > 0.
4. App nhận PaymentResponse và đọc lại OrderResponse. Khi đọc lại thất bại sau khi tiền đã được ghi nhận, chọn tải lại để xác minh; không tạo payment mới.
5. Chọn Hoàn tất đơn và xác nhận. Nếu còn dòng chưa SERVED và có quyền ORDER_MARK_SERVED, xác nhận đã phục vụ thực tế tất cả món trước khi gửi. App gọi mark-served hàng loạt rồi complete bằng version mới trả về. Khi tất cả món đã SERVED, chỉ gọi complete. Đơn tại bàn đóng đúng phiên bàn trong cùng transaction backend; app không gọi thêm /close.

Không gửi thao tác khi chỉ mở hộp thoại. Nếu còn món chưa SERVED và thiếu ORDER_MARK_SERVED, nút hoàn tất bị khóa cùng lý do. Không tự confirm đơn OPEN để vượt điều kiện backend.

## Thao tác món — bổ sung 18/10/2026

Chạm thẻ món đã lưu để mở hộp thoại. Nút chính tương ứng PENDING → Bắt đầu chế biến → COOKING; COOKING → Đã chế biến xong → READY; READY → Đã phục vụ → SERVED. Chỉ hiện bước kế tiếp, không tự gửi khi chạm thẻ. Dòng SERVED/CANCELLED không còn thao tác.

Hủy món dùng form lý do hiện có, chỉ khả dụng cho PENDING của đơn chưa trả tiền (UNPAID, paidAmount = 0). Theo backend hiện tại, COOKING cũng không được hủy. Đơn chưa confirm dùng ORDER_UPDATE; đơn đã confirm dùng ORDER_CANCEL. Lý do bắt buộc, tối đa 1000 ký tự.

Các bước chế biến/phục vụ chỉ áp dụng cho đơn CONFIRMED/PREPARING/READY/SERVED; đơn PAID vẫn có thể tiến trạng thái món. Hai bước bếp cần KITCHEN_DISPLAY cùng quyền thao tác tương ứng, không bắt buộc KITCHEN_VIEW để dùng chi tiết đơn. Đánh dấu phục vụ cần ORDER_MANAGEMENT + ORDER_MARK_SERVED. App vẫn yêu cầu ORDER_VIEW + ORDER_MANAGEMENT để mở chi tiết đơn.

## Kiến trúc

Luồng: Screen/Dialog → OrderSettlementController → RecordOrderPayment/CompleteOrder/GetOrderDetail → OrderRepository → OrderRepositoryImpl → OrderRemoteDataSource → authenticated Dio.

Thao tác từng món: OrderLineActions → OrderDetailController → TransitionOrderItem/CancelOrderItem → OrderRepository. Phục vụ hàng loạt trước hoàn tất: OrderCompletionDialog → OrderSettlementController → MarkAllOrderItemsServed → CompleteOrder. Controller giữ khóa OrderEvents suốt hai request; UI không tự gán trạng thái/version. OrderItemAction giữ ánh xạ endpoint, trạng thái nguồn/đích và quyền. Các điều kiện trạng thái đặt trong OrderAccessPolicy; quyền và feature dùng AccessPolicy.

- Domain: OrderPayment, OrderPaymentMethod, RecordOrderPaymentInput; hợp đồng repository/use case; canPay/canComplete trong OrderAccessPolicy. Tiền dùng MenuPrice chính xác theo phần trăm đơn vị, không dùng double để kiểm tra hoặc so sánh.
- Data: payment DTO/serializer riêng vì PaymentResponse khác OrderResponse. Response sai schema/đối tượng được báo lỗi để xác minh, không giả PAID hoặc tự cộng version.
- Presentation: controller riêng quản lý key, request bất biến, kết quả chưa xác định, receipt đã ghi nhận, đọc lại đơn và đối chiếu conflict. Widget chỉ trình bày và gọi controller.
- Provider: family theo orderId và orderScope; giữ controller khi còn thao tác cần xử lý. Cùng scope xoay token giữ intent; logout/đổi tenant/quyền/feature bỏ response cũ.
- Tích hợp: AccessPolicy, ApiErrorMapper, OrderEvents, OrderExitGuard và TableEvents. Hoàn tất phát refresh để danh sách bàn/chi tiết/phiên/chuyển bàn đọc dữ liệu mới; không tự giả bàn trống dựa trên payment.

## API

| Method | Path | Request | Response |
| --- | --- | --- | --- |
| POST | /api/v1/orders/{id}/payments | Idempotency-Key; expectedOrderVersion, paymentMethod CASH/TRANSFER, amount, referenceNo tùy phương thức | 201 mới / 200 replay, PaymentResponse |
| GET | /api/v1/orders/{id} | Không body | 200 OrderResponse mới |
| POST | /api/v1/orders/{id}/complete | expectedVersion của order | 200 OrderResponse COMPLETED |
| POST | /api/v1/orders/{id}/items/{lineId}/start-cooking | expectedOrderVersion của order | 200 OrderResponse, dòng COOKING |
| POST | /api/v1/orders/{id}/items/{lineId}/mark-ready | expectedOrderVersion của order | 200 OrderResponse, dòng READY |
| POST | /api/v1/orders/{id}/items/{lineId}/mark-served | expectedOrderVersion của order | 200 OrderResponse, dòng SERVED |
| POST | /api/v1/orders/{id}/mark-served | expectedOrderVersion của order | 200 OrderResponse, mọi dòng chưa hủy SERVED |

Không gửi restaurantId/currencyCode/paymentStatus. POST payment dùng expectedOrderVersion; complete dùng expectedVersion. Sau payment lấy version mới từ GET order. Không gọi confirm lần hai, không gọi close sau complete DINE_IN.

Thanh toán: CONFIRMED/PREPARING/READY/SERVED, UNPAID, paidAmount = 0, amount bằng totalAmount > 0. Chuyển khoản bắt buộc referenceNo đã trim, tối đa 100 ký tự. Hoàn tất: PAID, paidAmount = totalAmount > 0, ít nhất một dòng chưa hủy và tất cả dòng đó SERVED; backend kiểm tra thêm trạng thái phiên và nghĩa vụ các đơn liên quan.

## Quyền

- Ghi nhận tiền: PAYMENT_CREATE + PAYMENT_CONFIRM + PAYMENT_MANAGEMENT.
- Đọc đơn/readback: ORDER_VIEW + ORDER_MANAGEMENT. Không gọi GET thiếu quyền đọc.
- Hoàn tất TAKEAWAY: ORDER_COMPLETE + ORDER_MANAGEMENT.
- Hoàn tất DINE_IN: thêm TABLE_CLOSE + TABLE_MANAGEMENT; không yêu cầu TABLE_OPEN hoặc ORDER_CREATE.
- Phục vụ hàng loạt trước hoàn tất: thêm ORDER_MARK_SERVED + ORDER_MANAGEMENT; không yêu cầu feature bếp.
- Bắt đầu chế biến: KITCHEN_START_COOKING + KITCHEN_DISPLAY. Chế biến xong: KITCHEN_MARK_READY + KITCHEN_DISPLAY. Phục vụ từng món: ORDER_MARK_SERVED + ORDER_MANAGEMENT.
- Guard thanh toán kiểm tra policy riêng, vì showOrderDialog/OrderController.invoke cũ chỉ kiểm canOrders. Không bypass OWNER, giữ CASHIER/SUPER_ADMIN web-only như app hiện tại.

## Lỗi, retry và đồng thời

Một lần thanh toán chốt key và payload bất biến gồm version, phương thức, số tiền và mã tham chiếu. Khóa double tap và mutation khác trên cùng order; phối hợp khóa chuyển bàn. Timeout/mạng/5xx/response sai: giữ intent, chỉ retry chính xác key/body gốc. GET thấy PAID không xác nhận payment cụ thể và không làm mất key; cần response replay khớp để giải quyết kết quả chưa xác định.

PaymentResponse thành công nhưng GET lỗi: giữ receipt và trạng thái đã ghi nhận/chờ tải lại; chỉ GET lại, không POST thêm. Conflict đã xác định: giữ form, tải hiện trạng rồi người dùng chủ động đối chiếu; không tự thay version hoặc sinh key khác để vượt lỗi. Key xung đột giữ trạng thái cần đối chiếu và không retry mù.

Complete không có idempotency key. Khi timeout, GET lại; nếu đã COMPLETED thì áp dụng trạng thái, nếu chưa thì cần đối chiếu/xác nhận trước thao tác mới. Response trễ của scope cũ không thay dữ liệu scope hiện tại.

Mark-served hàng loạt và complete là hai transaction riêng. App áp dụng OrderResponse của bước phục vụ ngay khi thành công và dùng chính version đó cho complete; không cộng version thủ công. Nếu complete thất bại, các món vẫn giữ SERVED, không rollback UI. Timeout ở một trong hai bước yêu cầu tải lại và chủ động đối chiếu trước lần xác nhận mới; không tự tiếp tục chuỗi hoặc tự gửi lại. Sau CONCURRENT_ORDER_UPDATE tải lại đơn; không tạo order thay thế. Response sai ID, trạng thái đích hoặc version bị từ chối và yêu cầu xác minh.

Không đóng màn/rời luồng khi đang gửi hoặc còn kết quả cần xác minh. Khi backend đã ghi nhận tiền, lỗi GET không được hiển thị thành yêu cầu thanh toán lại.

## Xác minh

Kiểm thử dùng fake repository và Dio interceptor, không gọi backend thật. Bao gồm API/body/header/DTO, quyền và feature độc lập, điều kiện tiền/món, giữ key qua timeout, readback thất bại, conflict review, đổi scope, nút thanh toán → hoàn tất, form chuyển khoản và layout nhỏ với chữ 200%/bàn phím.

Kết quả trước phần thao tác món, ngày 17/10/2026:

- Phân tích tĩnh toàn dự án (`dart analyze`, SDK Dart đi kèm Flutter): **No issues found**.
- `flutter test --no-pub --reporter expanded`: **497/497 test đạt**, 59 giây; gồm 48 test mới cho settlement (12 domain/data, 21 controller, 6 tích hợp, 9 widget).
- Hồi quy có kiểm tra provider đổi scope khi payment đang gửi, receipt đã ghi nhận nhưng GET lỗi, version mới trước complete, refresh bàn sau complete và giao diện 320/800 px với chữ 200%/bàn phím.
- Cập nhật các test append theo contract hiện tại cho OPEN/CONFIRMED/PREPARING/READY/SERVED chưa trả tiền; giữ kiểm tra từ chối order terminal hoặc có nghĩa vụ thanh toán. Golden chọn bàn được cập nhật theo viền/màu bàn đã yêu cầu và đã đối chiếu ảnh.
- `git diff --check`: đạt. Không thêm dependency, không thay đổi backend hoặc gọi dữ liệu nhà hàng thật.

Chưa build APK hoặc xác nhận với thiết bị/backend thật trong phiên triển khai.

Kết quả sau phần thao tác món, ngày 18/10/2026:

- `dart analyze`: **No issues found**.
- `flutter test --no-pub --reporter expanded`: **523/523 test đạt**, 69 giây; thêm 26 test cho thao tác món và chuỗi phục vụ → hoàn tất (16 domain/data/controller, 10 widget).
- Kiểm tra endpoint/body/version, quyền bếp độc lập, từ chối hủy COOKING/đơn đã thanh toán, giữ món CANCELLED khi phục vụ hàng loạt, khóa thao tác trùng, complete dùng version mới, phục vụ thành công nhưng complete conflict, timeout không tự tiếp tục và response trễ khi đổi scope.
- Widget kiểm tra chạm món chưa gửi POST, xác nhận từng bước, form lý do hủy, xác nhận phục vụ hàng loạt và giao diện 320/800 px với chữ 200%/bàn phím. Bố cục giá/thao tác xuống dưới mô tả ở màn nhỏ để tránh tràn khi cuộn tới món.
- `git diff --check`: đạt. Không thêm dependency, không thay đổi backend. Chưa gọi API thật hoặc kiểm tra trên thiết bị thật.
