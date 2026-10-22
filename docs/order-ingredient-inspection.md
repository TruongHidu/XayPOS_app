# Công thức đã chốt và giữ/tiêu thụ nguyên liệu

Triển khai Flutter ngày 21/10/2026, theo ba contract backend:
`order-recipe-snapshot-api.md`, `order-inventory-allocation-api.md`,
`order-inventory-allocation-fe-sync.md`. Không sửa backend hoặc thêm dependency.

## Vị trí và cách sử dụng

Vào **Đơn hàng → Chi tiết đơn → Xem nguyên liệu** trên từng dòng món đã lưu.
Nút đọc độc lập với thao tác chuyển trạng thái/hủy món, nên vẫn dùng được với
món SERVED/CANCELLED và đơn kết thúc khi còn quyền đọc.

- **Công thức đã chốt**: tải khi mở cửa sổ; xem phiên bản, thời điểm chốt,
  lượng cả mẻ, hao hụt, lượng cần cho dòng món và cờ theo dõi kho.
- **Giữ & tiêu thụ kho**: tải riêng khi mở tab lần đầu; hiển thị trạng thái,
  ID kho lịch sử, thời điểm và lượng nguyên liệu đã chốt.
- **Làm mới/Thử lại**: chỉ tải phần đang chọn. Lỗi một phần không xóa phần kia.
- **Xem giao dịch tiêu thụ**: mở lịch sử với `orderId`, `orderItemId`,
  `sourceType=ORDER_ITEM`, `transactionType=RECIPE_USE`.

Desktop dùng bảng nguyên liệu; điện thoại/chữ lớn dùng card. Tên dài xuống dòng
hoặc có tooltip trong bảng. Header/đóng và footer/làm mới nằm ngoài vùng cuộn.
Không thêm sidebar, GET cho mỗi card đơn, hoặc GET allocation cho queue KDS.
Giỏ cục bộ không có nút gọi API lịch sử này.

## Quyền và API

| Phần | Permission đồng thời | Feature đồng thời |
| --- | --- | --- |
| Snapshot | ORDER_VIEW, RECIPE_VIEW | ORDER_MANAGEMENT, RECIPE_MANAGEMENT |
| Allocation | Các quyền snapshot và INVENTORY_VIEW | Các feature snapshot và INVENTORY_MANAGEMENT |
| Ledger | INVENTORY_VIEW | INVENTORY_MANAGEMENT |

`AccessPolicy.canViewOrderRecipeSnapshot` và `canViewOrderItemAllocation` giữ
guard tài khoản/role/tenant/subscription hiện có của ứng dụng. Không thêm quyền
ghi, MENU_VIEW hay INGREDIENT_VIEW. Ledger không yêu cầu quyền recipe/order;
chỉ hiện **Xem đơn** khi có ORDER_VIEW và feature order tương ứng.
Các quyền command order/KDS/QR được giữ nguyên.

Hai endpoint GET mới dùng authenticated Dio, `Accept: application/json`, đọc
JSON giữ chính xác số. Không gửi body/query, restaurantId, version hoặc key:

```text
/api/v1/orders/{orderId}/items/{orderItemId}/recipe-snapshot
/api/v1/inventory/orders/{orderId}/items/{orderItemId}/allocation
```

Remote kiểm tra orderId/orderItemId trả về đúng đối tượng yêu cầu. API không dùng
trong public QR. Response no-store chỉ tồn tại trong phiên cửa sổ; đóng/mở lại
tải mới. Không lưu database/local storage, không polling.

## Ý nghĩa dữ liệu

Snapshot thuộc order, là công thức lịch sử bất biến khi gửi/chấp nhận món.
`recipeVersion` là phiên bản nghiệp vụ, không phải optimistic-lock version.
`recipeQuantity` là lượng cả mẻ; `requiredQuantity` là lượng server chốt cho dòng
món, hiển thị nổi bật và không tính lại phía client. Nguyên liệu không theo dõi
tồn vẫn xuất hiện. Snapshot không thể hiện giá vốn hoặc quyết định allocation.

| snapshotStatus | Hiển thị |
| --- | --- |
| CAPTURED | Phiên bản và các nguyên liệu đã chốt |
| NO_RECIPE | Chưa có công thức khi gửi món |
| FEATURE_DISABLED | Chưa bật công thức khi gửi món |
| LEGACY_UNAVAILABLE | Dòng cũ chưa có lịch sử |
| NOT_SUBMITTED | Chưa gửi, chưa chốt |

Các trạng thái thiếu công thức là kết quả 200 hợp lệ. Không lấy công thức active
hoặc cost-estimate để điền lịch sử. Lượng/đơn vị dòng món vẫn được hiển thị.

Allocation thuộc inventory, là quyết định giữ/tiêu thụ đã lưu:

| status | Ý nghĩa |
| --- | --- |
| RESERVED | Giữ nguyên liệu, tồn vật lý chưa giảm |
| CONSUMED | Đã giảm tồn vật lý và ghi giao dịch tiêu thụ |
| RELEASED | Giải phóng lượng giữ, không phải nhập thêm tồn |
| SKIPPED | Không áp dụng; hiển thị lý do đã lưu |
| NOT_SUBMITTED | Chưa có allocation cho dòng chưa gửi |

SKIPPED dịch đủ năm lý do: chưa bật kho, chưa có công thức, chưa bật công thức,
không có nguyên liệu theo dõi tồn, dữ liệu cũ chưa khả dụng. Không giữ chỗ lại
cho lịch sử cũ. CAPTURED có thể cùng tồn tại với SKIPPED/LEGACY_UNAVAILABLE.
CONSUMED/RELEASED giữ các dòng nguyên liệu lịch sử. ID kho lấy từ allocation,
có thể chọn/copy đầy đủ; không thay bằng kho mặc định hiện tại, không cần GET
kho/nguyên liệu hiện tại để mở lịch sử. Không có nút reserve/consume/release.

## Tồn và lịch sử kho

Balance đọc bắt buộc ba trường: **Tồn vật lý** (`quantity`), **Đang giữ**
(`reservedQuantity`), **Khả dụng** (`availableQuantity`). Áp dụng cả danh sách,
cảnh báo, chi tiết/ngưỡng và picker nguyên liệu kho. Parser kiểm tra:

```text
0 <= reservedQuantity <= quantity
availableQuantity = quantity - reservedQuantity
configured=false: cả ba bằng 0, balanceId/version nullable theo contract
```

Không mặc định trường thiếu thành 0. `lowStock` vẫn dựa tồn vật lý và ngưỡng;
không thay bằng khả dụng hoặc thêm sort server chưa hỗ trợ. Request chỉnh ngưỡng
chỉ gửi minQuantity và version theo contract cũ.

Ledger hỗ trợ lọc nguồn, RECIPE_USE và deep link theo đơn/dòng món. Bộ lọc đi
xuyên query → serializer → remote guard → controller → provider target → route.
Link chứa enum không hợp lệ không tạo request bỏ lọc. Link từ balance/chứng từ
vẫn hoạt động. Không GET từng order để lấy mã; hiển thị ID rút gọn và tooltip.

| Nguồn | Chứng từ | Order/dòng món | Đơn giá |
| --- | --- | --- | --- |
| STOCK_DOCUMENT | Giữ thông tin và liên kết chứng từ | null | Giá server, có thể bằng 0 |
| ORDER_ITEM / RECIPE_USE | null, không mở chứng từ | Có ID đơn/dòng, reservation/usage | null → **Chưa định giá** |

Parser kiểm tra nullable theo nguồn, dấu âm RECIPE_USE và
`beforeQuantity + quantityChange = afterQuantity`. Trước/sau là tồn vật lý tại
thời điểm giao dịch. Không lấy giá tham chiếu/ước tính công thức thay đơn giá
null, không suy ra lợi nhuận thực tế. Chưa có giao dịch cho RESERVED/RELEASED là
hợp lệ; empty state không tạo dữ liệu giả.

## Kiến trúc và refresh

```text
OrderDetailScreen → OrderIngredientsButton → OrderIngredientDialog
  → ScopedReadController<OrderRecipeSnapshot> / ScopedReadController<OrderItemAllocation>
  → GetOrderItemRecipeSnapshot / GetOrderItemAllocation
  → repository contract → repository implementation → remote → authenticated Dio
```

Domain thuần Dart, entity snapshot/allocation độc lập. Cửa sổ presentation kết
hợp hai kết quả; không gộp state đọc vào giỏ hoặc controller mutation.
`IngredientQuantity` trong core dùng BigInt scale 3, đủ NUMERIC(14,3), không dùng
double tính lượng, không phụ thuộc data/presentation của feature kho.
Read JSON dùng decoder giữ lexeme số; không áp dụng quy tắc tiền HALF_UP của
cost-estimate cho requiredQuantity đã CEILING từ backend.

Provider autoDispose theo order/item và scope. Request generation loại response
trễ sau đóng/refresh/đổi scope. Đổi người dùng/tenant/quyền/feature/logout bỏ dữ
liệu và đóng cửa sổ; token refresh cùng scope giữ cửa sổ. Khởi tạo GET bằng
microtask ngoài build. Scroll dùng PageStorageKey tách theo dòng/tab; không dùng
chung key bool của ExpansionTile với offset double của scrollable.

OrderEvents sau command thành công đánh dấu snapshot/allocation đang mở cần
làm mới. InventoryEvents phát signal orderStock với warehouseId=null khi chưa
biết kho; balance/history được quan sát sẽ tải lại theo quyền, coalesce các
signal cùng lượt. Không đoán kho mặc định và không GET allocation để tìm kho.
Các event chỉ khóa/mở khóa command không gây GET dư.

Chi tiết ngưỡng giữ bản nhập khi nhận event và vô hiệu hóa lưu tới khi tải lại
baseline. Nút tải lại yêu cầu xác nhận việc thay bản nhập theo luồng ngưỡng cũ.
Chỉ backend quyết định reserve/consume/release; FE không tự trừ kho khi mark-ready,
phục vụ, thanh toán, complete hoặc tự hoàn tồn khi refund.

ApiErrorMapper bổ sung các lỗi snapshot/allocation, thiếu kho mặc định, thiếu tồn
khả dụng, invariant, đơn vị, phạm vi số, còn reservation và concurrency. Không
parse message để quyết định logic. QR thiếu tồn giữ PENDING, cần review mới;
không tự reject/approve/hash. Quy tắc giữ giỏ và frozen intent/key/body khi timeout
tiếp tục dùng controller hiện có; không gửi command tự động để vượt lỗi.

## File chính

- `lib/features/order/domain/entities/order_recipe_snapshot.dart`, repository và use case đọc mới.
- `lib/features/order/data/{dto,data_sources,repositories}/order_recipe_snapshot_*.dart`.
- `lib/features/order/presentation/providers/order_recipe_snapshot_providers.dart`.
- `lib/features/order/presentation/widgets/order_ingredient_dialog.dart` và điểm mở ở OrderDetailScreen.
- `lib/features/inventory/{domain,data}/…/order_item_allocation*.dart`, use case `get_order_item_allocation.dart`.
- `lib/features/inventory/presentation/providers/order_item_allocation_providers.dart`.
- InventoryDto/InventoryBalance, StockDocumentDto/InventoryTransaction, StockHistoryTarget và router.
- Balance/list/detail controller, InventoryEvents và các widget balance/threshold/ledger/picker.
- `lib/core/{values/ingredient_quantity.dart,network/read_json.dart,network/historical_read.dart,ui/controllers/scoped_read_controller.dart}`.
- `test/features/order/order_ingredient_{data,widget}_test.dart`, `test/features/inventory/order_stock_test.dart`.
- Fixture/test hiện có của inventory và QR; `tool/verify_order_ingredient_precision.dart`.

## Xác minh

Test mới bao phủ path/header/identity, mọi status/skip reason/nullable, quyền đọc
độc lập, ledger inventory-only/trộn nguồn/null cost, balance/invariant, event
không biết kho, giữ bản nhập ngưỡng, QR thiếu tồn, lazy GET, đóng/mở cửa sổ,
response trễ, token rotation/logout. Kiểm tra width 320/600/800/1200/1440, chữ
100%/200%, tên dài, đổi tab và scroll. Đã kiểm tra ảnh render dialog và kho ở
320/1200 px. Kiểm tra dart2js + Node với 99999999999.999 và 0.001 đạt.

- Formatter: các file Dart thay đổi đã định dạng.
- `dart analyze`: **No issues found**.
- `flutter test --reporter expanded`: **700/700 bài đạt** (bao gồm regression hiện có).
- Dart compile JavaScript và chạy Node: kiểm tra định lượng lớn/nhỏ đạt.
- Một lượt test render riêng tạo tám ảnh dialog/balance/ledger 320/1200 px đạt;
  công cụ chụp tạm đã được gỡ khỏi workspace.

Chưa xác nhận end-to-end với backend đang chạy, nhiều thiết bị đồng thời hoặc
thiết bị thật. Không chạy mutation lên dữ liệu nhà hàng thật.
