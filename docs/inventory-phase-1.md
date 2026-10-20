# Inventory — giai đoạn 1

## Phạm vi và cách dùng

Mục **Kho** có sẵn trên sidebar mở `/app/inventory`, mặc định ở tab **Tồn kho**.
Màn hình dùng toàn bộ chiều rộng AppShell, không tạo AppBar/Scaffold lồng nhau.

- **Tồn kho**: chọn kho, tìm theo tên/SKU, lọc trạng thái nguyên liệu, sắp xếp và phân trang từ server. Xem tồn, đơn vị cơ sở, ngưỡng và các nhãn trạng thái; mở chi tiết hoặc sửa ngưỡng nếu có quyền.
- **Kho**: danh sách kho, tạo/sửa thông tin, bật/tắt, đặt mặc định, xóa mềm và xem chi tiết. Các thao tác đổi trạng thái/default/xóa cần xác nhận đối tượng sau khi tải chi tiết mới nhất.
- **Cảnh báo tồn thấp**: xem một kho hoặc tất cả kho. Mỗi dòng có mã kho. Tab và request chỉ có khi được cấp thêm `LOW_STOCK_ALERT`.

Bộ chọn kho hỗ trợ tìm kiếm và phân trang; kho đang chọn được giữ độc lập với trang kết quả. Lần đầu chọn kho mặc định nếu có trên trang đang tải; nếu chưa tìm thấy, người dùng chọn kho. Kho đang chọn bị xóa sẽ được bỏ chọn rõ ràng. Không tải tất cả kho/balance để phân trang phía client.

Desktop dùng bảng có cuộn ngang khi cần. Điện thoại và chế độ phóng chữ dùng card co giãn chiều cao. Tìm kiếm luôn hiện; filter nâng cao trên màn nhỏ nằm trong vùng **Lọc và sắp xếp** có thể mở/thu gọn. Filter, tab và nút xuống dòng theo chiều rộng. Dialog cuộn được khi bàn phím mở. Refresh giữ kết quả cũ và hiển thị tiến trình; lỗi tải lại được phân biệt với kết quả rỗng.

Số kết quả lấy từ `totalElements` của query đang xem. Số lượng luôn đi kèm `baseUnit`; không cộng các đơn vị khác nhau, không quy đổi và không định dạng tiền tệ.

Giai đoạn này chỉ sửa `minQuantity`. Chưa có chứng từ nhập/xuất/điều chỉnh, lịch sử biến động, tự trừ tồn theo order hoặc chỉnh trực tiếp `quantity`. Backend, dependency và CRUD nguyên liệu không thay đổi.

## Cấu trúc và luồng phụ thuộc

```text
lib/features/inventory/
  domain/
    entities/          Warehouse, InventoryBalance, InventoryQuantity, query/input typed
    policies/          InventoryValidation
    repositories/      WarehouseRepository, InventoryBalanceRepository
    use_cases/         11 use case tương ứng API giai đoạn 1
  data/
    dto/               InventoryDto, InventoryRequests
    data_sources/      InventoryRemoteDataSource
    repositories/      Implementation và mapper lỗi Inventory
  presentation/
    controllers/       Danh sách kho, selector, danh sách tồn/cảnh báo, chi tiết/ngưỡng
    providers/         Dependency injection, scope, access recovery, controller families
    screens/           InventoryManagementScreen
    widgets/           Bộ lọc, phân trang, bảng/card, picker và dialog
```

```text
Widget → ChangeNotifier controller → Use case → Repository interface
       → Repository implementation → Remote data source → authenticated Dio
```

Domain không phụ thuộc Flutter/Dio/Riverpod. Widget dùng entity/input typed, không dựng payload HTTP. `InventoryRemoteDataSource` dùng authenticated Dio từ cấu hình môi trường có sẵn; không có base URL riêng hay `restaurantId` trong request.

Controller được tách theo trách nhiệm:

- `WarehouseListController`: query danh sách, chi tiết, CRUD/lifecycle kho và đối chiếu create timeout.
- `WarehouseSelectorController`: query picker, kho được chọn, đồng bộ thay đổi kho/default.
- `InventoryBalanceController`: danh sách tồn theo warehouseId; cùng controller hỗ trợ query low-stock độc lập. Low-stock có sort mặc định `quantity asc`.
- `InventoryBalanceDetailController`: tải số dư và trạng thái kho, giữ baseline, cập nhật ngưỡng.
- `InventoryEvents`: khóa thao tác theo resource, yêu cầu đối chiếu và phát thay đổi theo warehouseId/ingredientId.

Provider danh sách kho/selector giữ filter trong scope. Provider tồn/cảnh báo và chi tiết được tạo theo định danh, bỏ response trễ sau đổi query/kho hoặc dispose. Chi tiết đang gửi hoặc có kết quả chưa xác minh được giữ sống để không mở lại form rồi gửi lặp.

Các file tích hợp: `lib/app/providers.dart`, `lib/app/router/app_router.dart`, `lib/app/router/app_routes.dart`, `lib/core/auth/access_policy.dart`, `lib/core/ui/shell/app_shell.dart`, `lib/core/ui/sidebar/sidebar_filter.dart`. Registry sidebar đã có mục Kho nên không thêm mục trùng.

## API, quyền và feature

Prefix: `/api/v1/inventory`. Response entity/page trực tiếp, không bọc `data`.
Tất cả thao tác trong workspace yêu cầu `INVENTORY_VIEW` và feature `INVENTORY_MANAGEMENT`, cùng quyền riêng của thao tác:

| Method và đường dẫn | Quyền thao tác | Thành công |
| --- | --- | --- |
| `GET /warehouses` | `INVENTORY_VIEW` | 200 page kho |
| `GET /warehouses/{w}` | `INVENTORY_VIEW` | 200 Warehouse |
| `POST /warehouses` | `WAREHOUSE_CREATE` | 201 Warehouse |
| `PATCH /warehouses/{w}` | `WAREHOUSE_UPDATE` | 200 Warehouse |
| `PATCH /warehouses/{w}/status` | `WAREHOUSE_UPDATE` | 200 Warehouse |
| `POST /warehouses/{w}/make-default` | `WAREHOUSE_UPDATE` | 200 Warehouse |
| `DELETE /warehouses/{w}?expectedVersion=n` | `WAREHOUSE_DELETE` | 204, không parse JSON |
| `GET /warehouses/{w}/balances` | `INVENTORY_VIEW` | 200 page tồn |
| `GET /warehouses/{w}/balances/{i}` | `INVENTORY_VIEW` | 200 InventoryBalance |
| `PATCH /warehouses/{w}/balances/{i}/threshold` | `INVENTORY_THRESHOLD_UPDATE` | 200 InventoryBalance |
| `GET /low-stock` | `INVENTORY_VIEW` + feature `LOW_STOCK_ALERT` | 200 page tồn thấp |

Query kho: `q`, `active`, `page`, `size`, `sortBy`, `direction`.
Sort kho: `code`, `name`, `createdAt`, `updatedAt`.

Query tồn: `q`, `ingredientActive`, `page`, `size`, `sortBy`, `direction`.
Sort tồn/cảnh báo: `ingredientName`, `sku`, `quantity`, `minQuantity`, `updatedAt`.
Low-stock có thêm `warehouseId` optional. Page bắt đầu 0, size mặc định 20, tối đa 100. Search debounce 350 ms; đổi bộ lọc reset page. Trang cuối rỗng sau thay đổi được tải lại ở trang còn hợp lệ.

Không yêu cầu `MENU_VIEW`/`INGREDIENT_VIEW` để xem tồn; thông tin nguyên liệu lấy trực tiếp từ balance response, không GET chi tiết từng nguyên liệu/kho để dựng danh sách. Chi tiết/ngưỡng tải một số dư và một kho để kiểm tra trạng thái hoạt động.

`AccessPolicy.canInventory/inventoryScope` được dùng ở route, sidebar, UI và controller. Giữ chính sách CASHIER/SUPER_ADMIN hiện có và không bypass quyền OWNER. Scope gồm user, tenant, role, permission, feature, subscription ID/status. Token xoay cùng scope giữ filter/form; thay scope hoặc logout thay controller và đóng cả dialog/confirmation cũ.

## Logical balance, số lượng và version

Khóa dòng tồn là `warehouseId + ingredientId`, không phải `balanceId`.

Một balance hợp lệ có thể là:

```json
{
  "configured": false,
  "balanceId": null,
  "version": null,
  "createdAt": null,
  "updatedAt": null,
  "quantity": 0,
  "minQuantity": 0,
  "lowStock": false
}
```

Đây là tồn logic chưa có bản ghi vật lý, hiển thị **Chưa cấu hình**. GET không tạo bản ghi. Lưu ngưỡng 0 trên balance logic có thể trả nguyên balance logic, version vẫn null. Không tự gọi API tạo dữ liệu bổ sung.

`InventoryQuantity` giữ số nguyên thousandths, cho phép 0, tối đa `99999999999.999`. Giá trị scaled tối đa `99999999999999`, dưới giới hạn số nguyên chính xác của JavaScript. Parse/so sánh bằng số nguyên; không làm tròn input quá 3 chữ số thập phân. Chỉ serializer chuyển sang JSON number. Form dùng dấu chấm thập phân; hiển thị dùng dấu phẩy và đơn vị server.

Ngưỡng 0 có nhãn **Đã tắt cảnh báo**; ngưỡng >0 và tồn <= ngưỡng là tồn thấp. UI dùng cờ `lowStock` server, màu cam kèm chữ, không tự ghi trạng thái server. Nguyên liệu inactive có nhãn riêng, vẫn đọc được khi API trả về.

Threshold chỉ gửi `{expectedVersion, minQuantity}`. `expectedVersion: null` và `expectedVersion: 0` được giữ khác nhau. Kho inactive chỉ cho xem tồn.

Create chỉ gửi code trim/uppercase và name trim; backend quyết định default/active. Edit chỉ gửi trường code/name thay đổi và version. Status/default là API riêng. Delete dùng version trên query. Không gửi Idempotency-Key ngoài contract. Version luôn lấy từ response; no-op thành công có thể không tăng version.

UI/controller chặn tắt/xóa kho mặc định và đặt mặc định kho inactive. Không suy luận kho hết tồn từ một trang balances. Backend quyết định điều kiện còn tồn khác 0; lỗi `WAREHOUSE_HAS_STOCK` được giữ và giải thích bằng tiếng Việt.

## Lỗi, xung đột và timeout

Repository dùng Result/Failure và ApiErrorMapper hiện có, bổ sung phân loại HTTP cho code Inventory chưa có trong mapper chung. Hỗ trợ 400/401/403/404/409 và các code warehouse/not found/inactive/stock/concurrent update. Mã kho trùng hiển thị cạnh field code, bao gồm mã được giữ bởi kho xóa mềm. Lỗi quyền/feature đi qua access recovery có chống gọi lặp trong scope.

- Nhấn trùng: khóa dùng chung theo warehouse hoặc cặp warehouse/ingredient, không chỉ khóa nút ở một widget.
- Conflict version/inactive: giữ draft, khóa gửi tiếp và cho tải lại entity. Form có xác nhận trước khi thay draft bằng dữ liệu server, rồi dùng baseline mới. Không tự đổi version để gửi lại.
- Timeout/lỗi response khiến chưa rõ kết quả: không retry mutation tự động. Form yêu cầu đọc lại/đối chiếu trước thao tác tiếp; kết quả chưa rõ chặn đóng form cho đến khi kiểm tra được hoặc scope thay đổi.
- Create timeout: giữ mã/tên ban đầu, tìm theo mã và đối chiếu exact code đã chuẩn hóa, phân trang trên server. Không lặp POST. Sau khi xem kết quả, người dùng xác nhận đã đối chiếu để đóng hoặc nhập lại.
- Entity đọc lại trả 404: bỏ baseline không còn tồn tại, không tự tạo thay thế.
- Refresh thất bại: giữ dữ liệu lần trước và thông báo rõ, không biến lỗi thành tồn 0.

## Điểm nối giai đoạn 2

Tái sử dụng `WarehouseSelectorController`, các query typed, `InventoryQuantity`, formatter, Inventory scope và hai repository hiện tại.

Chứng từ và biến động sẽ có model/repository/use case riêng trong feature Inventory. Sau khi backend xác nhận chứng từ, phát sự kiện trong scope hiện tại:

```dart
ref.read(inventoryEventsProvider).emit(
  InventoryChange(
    InventoryChangeKind.balance,
    warehouseId,
    ingredientId: ingredientId, // bỏ nếu thay đổi nhiều nguyên liệu trong kho
  ),
);
```

Danh sách tồn đúng kho và low-stock liên quan tải lại; kho khác không bị tải lại vì sự kiện balance đó. Thay đổi kho làm mới danh sách/picker và chi tiết kho đang chọn, bao gồm default cũ khi kho khác vừa được đặt default. Không sửa quantity trong warehouse/threshold controller, không gộp balances vào Ingredient của menu. Chưa tạo model/repository rỗng cho API giai đoạn 2.

## Kiểm thử và giới hạn

Các kiểm thử nằm ở `test/features/inventory/`:

- `inventory_data_test.dart`: đủ 11 endpoint/method/query/body/status, DELETE 204, null/0/no-op, logical balance, precision/giới hạn, lỗi và phản hồi sai định danh/version.
- `inventory_controller_test.dart`: quyền/feature/route/sidebar, low-stock bị khóa, inactive/default/stock, no-op, khóa nhấn trùng, conflict/timeout/readback, response trễ, event theo kho, đồng bộ default cũ/mới và trang cuối.
- `inventory_widget_test.dart`: ba tab ở 320/600/800/1200/1440 px, chữ hệ thống 100%/200%, form khi bàn phím mở, draft/validation/conflict, xác nhận lifecycle, scope và quyền chỉ xem.

Lệnh xác minh: `dart analyze`, `flutter test test/features/inventory --reporter expanded`, `flutter test --reporter expanded`.

Kết quả ngày 18/10/2026:

- Static analysis: không có lỗi/cảnh báo.
- 41 kiểm thử Inventory vượt qua.
- Đã render và kiểm tra trực quan bản desktop 1440 px, điện thoại 320 px bằng fixture có số dư vật lý, logic, tồn thấp và nguyên liệu inactive.
- Toàn bộ 586 kiểm thử của dự án vượt qua, gồm hồi quy nguyên liệu, công thức, order, payment, tables, QR và các feature hiện có.

Kiểm thử dùng repository fake/Dio interceptor, chưa kết nối backend thật hoặc thao tác trên thiết bị vật lý. Không coi kết quả này là kiểm chứng dữ liệu production, tenant hay hiệu năng API thực tế.
