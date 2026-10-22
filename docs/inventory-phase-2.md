# Inventory — giai đoạn 2

Ngày 22/10/2026 bổ sung `stockAuditId` cho chứng từ sinh từ
[kiểm kê](inventory-phase-7.md). Chứng từ này chỉ đọc; quyền xem chứng từ kho không
đòi thêm feature kiểm kê. Xem [cảnh báo có lịch sử](inventory-phase-6.md) cho phần ACK.

Cập nhật 21/10/2026: ledger hỗ trợ thêm nguồn ORDER_ITEM/RECIPE_USE và giá chưa định giá.
Xem [bàn giao nguyên liệu theo món](order-ingredient-inspection.md) cho bộ lọc và luồng liên quan.

## Sử dụng

Mục **Kho** (`/app/inventory`) giữ các vùng Tồn kho, Kho và Cảnh báo tồn thấp; bổ sung **Chứng từ** và **Biến động**. Cảnh báo chỉ hiện khi có `LOW_STOCK_ALERT`; chứng từ và lịch sử không cần feature này.

Luồng thông thường:

1. Vào **Chứng từ**, chọn tạo phiếu nhập, xuất hoặc điều chỉnh theo quyền được cấp.
2. Chọn kho đang hoạt động, nhập ghi chú, thêm nguyên liệu, số lượng và đơn giá vốn. Phiếu điều chỉnh chọn tăng/giảm trên từng dòng. Đơn vị chỉ đọc từ snapshot server.
3. Chọn **Lưu nháp**. Có thể lưu nháp rỗng. Lúc này tồn chưa thay đổi.
4. Ở chi tiết, tiếp tục thêm/sửa/xóa dòng hoặc sửa ghi chú. Mỗi thao tác lưu dùng version của toàn chứng từ.
5. Chọn **Xác nhận chứng từ**, kiểm tra phiếu/kho/loại/số dòng/tác động và xác nhận ghi nhận tồn. Backend xử lý cả phiếu trong một transaction. Một dòng thiếu tồn hoặc không hợp lệ thì cả lần ghi nhận bị từ chối.
6. Phiếu xác nhận chỉ đọc; chọn **Xem biến động** để xem ledger theo đúng documentId. Phiếu nháp có thể hủy; hủy nháp không thay đổi tồn.

Khi đổi kho hoặc loại của phiếu chưa lưu, UI yêu cầu xác nhận nếu cần bỏ các dòng đang nhập. Phiếu đã lưu không đổi kho/loại. Muốn đổi nguyên liệu của dòng đã lưu phải xóa dòng rồi thêm dòng mới.

Phiếu đang soạn có nút tiếp tục trên danh sách. Yêu cầu tạo chưa xác minh được giữ riêng và có nút khôi phục. Tạo phiếu khác không âm thầm bỏ một yêu cầu chưa rõ kết quả.

Các route:

| Route | Nội dung |
| --- | --- |
| `/app/inventory?tab=documents` | Workspace mở tab Chứng từ |
| `/app/inventory?tab=transactions` | Workspace mở tab Biến động |
| `/app/inventory/stock-documents/new` | Tạo chứng từ |
| `/app/inventory/stock-documents/:documentId` | Chi tiết chứng từ |
| `/app/inventory/transactions` | Lịch sử, hỗ trợ query warehouseId/ingredientId/documentId |

Chi tiết tồn giai đoạn 1 có liên kết **Xem biến động** theo warehouseId + ingredientId, kể cả balance logic chưa có balanceId. Các màn hình tiếp tục dùng AppShell hiện tại, không thêm sidebar Kho hoặc Scaffold/AppBar lồng trong nội dung feature.

## Cấu trúc và phụ thuộc

Tiếp tục trong `lib/features/inventory/`:

| Tầng | File/thành phần chính | Trách nhiệm |
| --- | --- | --- |
| Domain | `entities/stock_document.dart` | Summary, detail, item, transaction và enum typed |
| Domain | `entities/stock_inputs.dart`, `stock_queries.dart` | Input, query, khoảng Instant inclusive, key generator interface |
| Domain | `entities/stock_numbers.dart` | Tiền chính xác, tổng số lượng, biến động có dấu, preview chính xác |
| Domain | `policies/stock_document_validation.dart` | Validation dòng/create, precision, tổng lưu trữ và giới hạn backend |
| Domain | `repositories/stock_document_repository.dart` | Hai interface chứng từ và ledger |
| Domain | `use_cases/stock_document_use_cases.dart` | 10 use case tương ứng API |
| Data | `dto/stock_json.dart` | Đọc số JSON nguyên bản trước khi biến thành double |
| Data | `dto/stock_document_dto.dart`, `stock_document_requests.dart` | Parse response, kiểm tra dữ liệu và serialize đúng payload |
| Data | `data_sources/stock_document_remote_data_source.dart` | Authenticated Dio, 10 endpoint, status và query |
| Data | `repositories/stock_document_repository_impl.dart` | Result/Failure và ánh xạ lỗi Inventory |
| Data | `stock_key_generator.dart` | Sinh key ngẫu nhiên cho một lần tạo logic |
| Presentation | `controllers/stock_document_create_controller.dart` | Draft cục bộ và creation intent bất biến/key cố định |
| Presentation | `controllers/stock_document_detail_controller.dart` | Baseline, khóa toàn chứng từ, mutation và readback |
| Presentation | `controllers/stock_document_list_controller.dart` | Search debounce 350 ms, filter, phân trang, bỏ response cũ |
| Presentation | `controllers/inventory_transaction_controller.dart` | Query/phân trang ledger và invalidation liên quan |
| Presentation | `providers/stock_document_providers.dart` | DI, controller theo scope/document, picker độc lập với workspace |
| Presentation | `screens/stock_document_*`, `inventory_transaction_screen.dart` | Màn hình create/detail/history |
| Presentation | `widgets/stock_*`, `inventory_transaction_list.dart` | Form dòng/note, picker, filter, bảng/card và confirmation |

Luồng phụ thuộc giữ nguyên:

```text
Widget → ChangeNotifier controller → Use case → Repository interface
       → Repository implementation → Remote data source → authenticated Dio
```

Domain không phụ thuộc Flutter/Dio/Riverpod. Widget không dựng HTTP payload. Không thêm dependency hoặc tạo framework state/decimal dùng chung cho toàn app.

Tích hợp ở providers, router/routes, AccessPolicy, InventoryManagementScreen và InventoryEvents. Giai đoạn 1 được mở rộng đúng các điểm này; logic CRUD kho/ngưỡng không nhận nhiệm vụ nhập/xuất.

## API, quyền và feature

Prefix `/api/v1/inventory`. Sử dụng authenticated Dio hiện có; không cấu hình URL riêng, không gửi restaurantId hoặc tự dựng documentCode. Response entity/page trực tiếp.

Tất cả chức năng cần `INVENTORY_MANAGEMENT` và quyền xem `INVENTORY_VIEW` trong workspace. Quyền mutation được kiểm tra theo loại chứng từ đã lưu:

| Loại | Quyền mutation |
| --- | --- |
| RECEIPT — Nhập kho | `INVENTORY_RECEIVE` |
| ISSUE — Xuất kho | `INVENTORY_ISSUE` |
| ADJUSTMENT — Điều chỉnh | `INVENTORY_ADJUST` |

Có quyền nhập không cho phép sửa/xác nhận/hủy phiếu xuất. Kiểm tra ở route/UI/controller; giữ chính sách OWNER/CASHIER/SUPER_ADMIN và scope hiện có. Không yêu cầu `MENU_VIEW`, `INGREDIENT_VIEW` hoặc `LOW_STOCK_ALERT` để lập chứng từ/xem ledger.

| Method | Đường dẫn | Request | Thành công |
| --- | --- | --- | --- |
| GET | `/stock-documents` | Query chứng từ | 200 page summary |
| GET | `/stock-documents/{d}` | — | 200 detail |
| POST | `/stock-documents` | Header Idempotency-Key; type/kho/note/items | **201** detail, kể cả replay |
| PATCH | `/stock-documents/{d}` | expectedVersion, note | 200 detail |
| POST | `/stock-documents/{d}/items` | expectedVersion và toàn bộ dòng | 200 detail |
| PATCH | `/stock-documents/{d}/items/{i}` | expectedVersion, quantity/cost/direction/note | 200 detail |
| DELETE | `/stock-documents/{d}/items/{i}` | Query expectedVersion, không body | **204**, không parse JSON |
| POST | `/stock-documents/{d}/confirm` | expectedVersion | 200 detail |
| POST | `/stock-documents/{d}/cancel` | expectedVersion | 200 detail |
| GET | `/transactions` | Query ledger | 200 page transaction |

Serializer không gửi unit, status, documentCode, restaurantId, thành tiền hoặc balance version trong mutation. PATCH dòng gửi cả quantity, unitCost, adjustmentDirection và note; không áp semantics PATCH sparse. Note trống được chuẩn hóa null; unitCost trống thành 0. Chỉ create chứng từ có Idempotency-Key; các mutation còn lại không tự thêm header này.

Document query: q (mã/ghi chú, tối đa 100 ký tự), type, status, warehouseId, createdFrom/createdTo, page/size/sortBy/direction. Sort: documentCode, documentType, status, createdAt, updatedAt, totalCost; mặc định createdAt desc.

Ledger query: warehouseId, ingredientId, **documentId**, transactionType, dates, paging; chỉ sort createdAt. Không có q. Response liên kết phiếu bằng **stockDocumentId**.

Phân trang server: page 0, size 20, tối đa 100; tổng kết quả dùng totalElements. Đổi filter reset page, trang cuối không còn kết quả được đưa về trang hợp lệ. Không tải hết dữ liệu để phân trang client.

Khoảng ngày chọn trên lịch dùng đầu ngày local và cuối ngày local, chuyển sang UTC. `createdFrom >=`, `createdTo <=`; cuối ngày tính tới microsecond cuối. Chứng từ lọc ngày tạo; ledger lọc thời điểm posting. Không áp giới hạn số ngày của module reports vào API này.

## Picker, snapshot và lifecycle

Picker nguyên liệu dùng `GET /warehouses/{w}/balances` và repository giai đoạn 1. Query/selection của picker được tách khỏi danh sách tồn workspace:

- Receipt filter ingredientActive=true.
- Issue/adjustment để active=null; nguyên liệu inactive vẫn được chọn, bao gồm điều chỉnh tăng theo backend.
- Bao gồm logical balance configured=false và SKU null.
- Vô hiệu nguyên liệu đã có trong phiếu, không GET chi tiết từng dòng.
- Đơn vị từ baseUnit; đơn giá nhập tay, mặc định 0, không gọi API giá/costPrice ngoài quyền.

Kho phải active khi tạo mới và confirm. Với nháp đã tồn tại, sửa ghi chú/dòng, xóa dòng và cancel không bị khóa chỉ vì kho inactive. Confirmation kiểm tra trạng thái kho và backend tiếp tục quyết định các điều kiện nguyên liệu/đơn vị/tồn.

Tên/SKU/unit trong chứng từ và ledger là snapshot từ server. Xem lịch sử không yêu cầu GET kho hiện tại thành công: kho đã xóa mềm hoặc nguyên liệu ngừng hoạt động không làm mất lịch sử. Không tự cập nhật đơn vị, quy đổi hoặc thay snapshot để bỏ qua `INGREDIENT_UNIT_CHANGED`.

Create hỗ trợ nháp rỗng; confirm cần ít nhất một dòng. Giới hạn 100 dòng áp dụng mảng items của request create; không áp cap 100 lên response hoặc giả định backend addItem cũng có cap này.

## Version và recovery

Version của mọi thao tác là **document.version**. Dòng không có version riêng. Khóa dùng chung theo toàn documentId, tránh sửa ghi chú và nhiều dòng song song bằng cùng một version.

Mutation áp dụng response server; không tự tăng version. No-op có thể giữ version. Sau DELETE 204, detail GET lấy lại snapshot/version. Nếu GET thất bại, giữ thông báo xóa thành công nhưng chặn mutation tiếp cho tới readback, không suy đoán version mới.

Conflict giữ dữ liệu đang nhập, khóa gửi tiếp và cho tải lại đúng document. Dialog note/dòng yêu cầu xác nhận trước khi thay baseline/draft; không tự cập nhật expectedVersion rồi gửi lại. Khi readback trả confirmed/cancelled, màn hình theo trạng thái terminal, không tạo phiếu thay thế.

Tạo chứng từ dùng creation intent riêng:

- Một key cho một payload bất biến, chống nhấn trùng cả lúc kiểm tra kho lẫn khi POST.
- Timeout, lỗi 500 hoặc response chưa xác minh: khóa chỉnh payload, giữ key và typed input để thử lại đúng yêu cầu ban đầu.
- Không dùng đường retry này cho create kho giai đoạn 1.
- Replay trả detail hiện tại, có thể đã CONFIRMED/CANCELLED, vẫn status 201. Không ép response phải DRAFT hoặc version khởi tạo cố định.
- `IDEMPOTENCY_KEY_REUSED` không tự xoay key. UI cho đối chiếu danh sách và xác nhận thủ công đã kiểm tra trước khi bỏ intent đó; không bịa GET-by-key.
- Add/edit/delete/confirm/cancel timeout không tự retry. Đọc lại đúng phiếu; chỉ thao tác tiếp sau đối chiếu.

Intent và draft được giữ trong provider theo scope, sống qua điều hướng và xoay token cùng scope. **Chưa lưu bền vững qua khởi động lại app**. Sau crash/restart phải kiểm tra danh sách trước khi lập phiếu mới; không tuyên bố chống trùng xuyên restart. Không có offline queue.

Scope gồm user, tenant, role, permissions, features và subscription. Scope thay đổi đóng các form/confirmation cũ, tạo state mới và bỏ response trễ. Không replay ý định của tenant cũ.

## Số chính xác và giới hạn backend

| Giá trị | Biểu diễn/giới hạn |
| --- | --- |
| Quantity dòng, tồn trước/sau | InventoryQuantity, 11 nguyên + 3 lẻ, quantity dòng >0 |
| QuantityChange | StockQuantityChange, BigInt có dấu, khác 0 |
| Tổng quantity chứng từ | StockQuantityTotal, BigInt, 13 nguyên + 3 lẻ |
| UnitCost | StockMoney, BigInt cents, 12 nguyên + 2 lẻ |
| Thành tiền dòng | StockMoney, 14 nguyên + 2 lẻ |
| Tổng giá trị chứng từ | StockMoney, 16 nguyên + 2 lẻ |

Không dùng double để tính toán/validation/so sánh. Preview tính BigInt; chỉ quantity/unitCost chuyển sang JSON number ở serializer. Các giá trị request này vẫn trong miền có thể round-trip đúng tới precision yêu cầu trên JavaScript.

Response stock APIs dùng `ResponseType.plain` và `request<dynamic>` để Dio không tự ép sang JSON/double trước khi đọc. `decodeStockJson` giữ token số nguyên bản, không can thiệp chuỗi ghi chú/ID, hỗ trợ notation exponent và chỉ áp dụng cho API stock. DTO từ token sang BigInt/scaled values. HTTP lỗi dạng text được giải mã để mapper còn giữ code/fieldErrors.

Server totalCost là giá trị chính thức. UI không dùng tổng quantity của các đơn vị khác nhau như một số tồn chung hoặc net adjustment. Tổng giá trị là giá trị chứng từ, không phải doanh thu/định giá tồn.

**Giới hạn backend đã xác minh:** `StockDocumentItem` đang gọi `quantity.multiply(unitCost).setScale(2)` mà chưa có rounding mode. Ví dụ 0.001 × 0.01 = 0.00001 sẽ cần làm tròn và backend có thể lỗi 500 dù từng field hợp precision. Frontend kiểm tra tích chính xác, báo lỗi tại đơn giá với giải thích giới hạn hiện tại; không tự làm tròn HALF_UP hoặc thay quantity/cost. Các tổng vượt precision lưu trữ cũng bị chặn trước mutation. Backend không thay đổi.

## Đồng bộ giai đoạn 1

InventoryEvents thêm kind document, documentId và resource key chứng từ. Create/sửa/xóa dòng/cancel nháp phát event document để refresh danh sách phiếu; không làm danh sách tồn/ledger tải như đã posting.

Confirm thành công hoặc readback xác minh CONFIRMED phát:

```dart
InventoryChange(InventoryChangeKind.document, warehouseId, documentId: documentId)
InventoryChange(InventoryChangeKind.balance, warehouseId, documentId: documentId)
```

Một event balance toàn kho được coalesce thành refresh liên quan, không phát hàng trăm request theo số dòng. Tồn đúng kho và ledger liên quan tải lại. Low-stock chỉ tải nếu có feature. Detail ngưỡng đang mở được đánh dấu baseline stale và giữ snapshot đang xem để người dùng tải lại/đối chiếu trước khi sửa.

Không client cộng/trừ quantity, không sửa threshold thay nhập/xuất, không xóa ledger. Backend xác nhận atomic toàn bộ, `INSUFFICIENT_STOCK` không giả thành công một phần.

## Lỗi và trải nghiệm

Repository giữ Result/Failure và mapper hiện có, bổ sung thông báo tiếng Việt cho code chứng từ/version/ingredient/stock/idempotency. Giữ HTTP status, code và fieldErrors. Validation hiển thị cạnh field/dòng hoặc panel tổng hợp. HTTP 401/403/feature/subscription tiếp tục dùng access recovery theo scope.

Desktop dùng bảng đủ chiều rộng hữu ích và có cuộn ngang khi cần. Màn nhỏ/phóng chữ dùng card co giãn, filter nâng cao thu gọn, nút xuống dòng. Dialog cuộn được khi bàn phím mở. Trạng thái dùng nhãn cùng màu, biến động có dấu +/- và đơn vị. Tiền có nhóm hàng nghìn; không quy đổi đơn vị/currency ngoài contract. Refresh lỗi giữ dữ liệu cũ và hiển thị thông báo thay vì biến thành tồn 0.

## Kiểm tra thực tế

Kiểm thử mới:

- `test/features/inventory/stock_document_data_test.dart`: 10 API, payload đầy đủ, status 201/204, null, expectedVersion, plain error response, no-op/replay terminal, signed ledger, response >100 dòng, precision/rounding và decoder thực của Dio với số lớn.
- `test/features/inventory/stock_document_controller_test.dart`: quyền theo loại, nháp rỗng, picker rules, khóa mutation, frozen create intent, timeout/conflict, readback, inactive warehouse, no-op, response trễ, event và filter/date. Có kiểm tra ngưỡng giai đoạn 1 bị đánh dấu stale sau posting.
- `test/features/inventory/stock_document_widget_test.dart`: luồng tạo → confirm → ledger, quyền chỉ xem/issue-only, giữ draft khi lỗi, điều hướng/token/logout, liên kết lịch sử từ logical balance, màn hình 320/600/800/1200/1440 px, chữ 100%/200% và dialog có bàn phím.
- `tool/verify_stock_precision.dart`: executable thuần Dart kiểm tra BigInt, số tổng lớn, JSON input round-trip và preview; đã compile JavaScript và chạy trên Node.

Lệnh:

```text
dart analyze
flutter test test/features/inventory --reporter expanded
flutter test --reporter expanded
dart compile js tool/verify_stock_precision.dart -o build/stock_precision.js
node -e "globalThis.self=globalThis; require('./build/stock_precision.js')"
```

Kết quả ngày 18/10/2026:

- `dart analyze`: không có lỗi, cảnh báo hoặc lint còn lại.
- **89 kiểm thử Inventory vượt qua**, gồm 41 kiểm thử giai đoạn 1 và 48 kiểm thử bổ sung giai đoạn 2.
- **Toàn bộ 634 kiểm thử của dự án vượt qua**, gồm hồi quy nguyên liệu, công thức, order, payment, tables, QR và các feature hiện có.
- Executable precision đã compile sang JavaScript và chạy thành công trên Node v22.23.2, bao gồm tổng tiền/số lượng lớn và JSON round-trip tại giới hạn request.
- Đã render và xem 8 bản desktop/điện thoại của danh sách, chi tiết, lịch sử và tạo phiếu ở 1440/320 px bằng fixture. Các kiểm thử widget riêng kiểm tra thêm chữ 200% và bàn phím.

Chưa gọi mutation lên backend thật, chưa kiểm thử thiết bị vật lý hoặc toàn bộ app trên trình duyệt thật. Kiểm tra JavaScript xác minh riêng đường số/JSON, không thay thế kiểm thử Flutter Web tích hợp. Chưa xác minh throughput/concurrency với database thật. Không thay đổi backend, schema, dependency hoặc các chức năng order/payment/QR.
