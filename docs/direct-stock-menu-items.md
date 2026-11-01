# Hàng bán sẵn trừ tồn trực tiếp (V40)

Một món trên thực đơn có thể tự là hàng tồn kho, không cần nguyên liệu hay công
thức 1:1. Hợp đồng API: `pos-saas-be/docs/direct-stock-menu-items-fe-sync.md`.

## Cấu hình trên form món

Form dùng `InventoryModeSelector`, gửi cùng các trường khác trong một request.

| Lựa chọn | trackInventory | recipeEnabled | Khi tạo món | Cần để bật |
| --- | --- | --- | --- | --- |
| Không theo dõi | false | false | Có | Không |
| Trừ tồn trực tiếp | true | false | Có | INVENTORY_MANAGEMENT |
| Sử dụng công thức | false | true | Không | RECIPE_MANAGEMENT + công thức hợp lệ |

`AccessPolicy.canSetInventoryMode` chỉ đòi feature khi bật chế độ mới, nên sau khi
hạ gói vẫn sửa được tên/giá và vẫn rời được chế độ cũ.

PATCH merge với giá trị đã lưu. `UpdateMenuItemInput.changes` chỉ gửi cờ khác
baseline, nên DIRECT ↔ RECIPE luôn gửi cả hai cờ trong một request. `inventoryMode`
chỉ đọc từ response, không bao giờ gửi.

Công tắc **Sử dụng công thức** chỉ gửi `recipeEnabled`, nên bị thay bằng ghi chú trên
món DIRECT. `RecipeApplicationController` chặn thêm trước khi lưu để không lưu công
thức rồi mới nhận 409. Lối vào công thức vẫn mở vì DIRECT → RECIPE cần công thức
hiện hành hợp lệ.

## Định danh hàng hóa

`ingredientId` là null với MENU_ITEM. Mọi entity kho dùng `stockItemId` + `itemType`
do `StockItemRefDto` parse; `ingredientId` đã bị xóa khỏi entity để compiler chặn
việc dùng nhầm làm khóa (`InventoryBalance.key`, kiểm tra trùng dòng, tập loại trừ).
Payload cũ chỉ có `ingredientId` được đọc là INGREDIENT.

| Tầng | Tên | Lý do |
| --- | --- | --- |
| Entity, dữ liệu FE | `stockItemId` | `itemId` đã là id dòng phiếu/kiểm kê |
| Body phiếu kho | `itemId` | Hợp đồng; `ingredientId` bị 400 với MENU_ITEM |
| Query/path balance, ledger, alert | `ingredientId` | Tên wire giữ nguyên, nhận UUID hàng hóa |
| Sort, filter | `ingredientName`, `ingredientActive` | Giá trị wire |

## Chọn hàng cho phiếu kho

Picker dùng API balance theo kho, không dùng `GET /inventory/stock-items`. Hai API
lọc cùng tập hàng và balance vẫn trả hàng chưa có tồn, lại kèm tồn vật lý, đang giữ,
khả dụng và lọc active trong một request. Stock audit và ngưỡng không có picker.

## Ledger và allocation

`DIRECT_USE` là giao dịch âm, nguồn ORDER_ITEM, chỉ hợp lệ với MENU_ITEM và không có
`recipeUsageId`. Đơn giá null hiển thị **Chưa định giá**, không phải 0.

Allocation chỉ cần ORDER_VIEW + INVENTORY_VIEW ở client; server kiểm tra quyền công
thức theo từng dòng vì app không biết chế độ của dòng trước khi đọc:

- Có quyền công thức: dialog như cũ.
- Chỉ có quyền kho: nút **Xem kho của món**, mở thẳng allocation, không gọi snapshot.
  Dòng không DIRECT bị 403 hiện thông báo thông tin, không phải lỗi.

Không suy ra chế độ từ NOT_SUBMITTED vì khi đó `directStockSnapshot` luôn là false.

## Lỗi và làm mới

| Mã | Xử lý |
| --- | --- |
| INVENTORY_TRACKING_MODE_CONFLICT, STOCK_TRACKING_CHANGE_NOT_ALLOWED | Hiện trên form, đổi lựa chọn rồi lưu lại được |
| STOCK_ITEM_UNIT_CHANGE_NOT_ALLOWED, STOCK_ITEM_DELETE_NOT_ALLOWED | Hiện lỗi, xử lý tồn/giữ chỗ/phiếu nháp trước |
| INVALID_STOCK_ITEM_REFERENCE | Lỗi nhập liệu của phiếu |
| INSUFFICIENT_AVAILABLE_STOCK | Giữ giỏ, không tự thử lại |
| INVENTORY_DEFAULT_WAREHOUSE_REQUIRED | Thêm link **Mở quản lý kho** trên màn hình nếu có WAREHOUSE_UPDATE |

Link kho được đẩy chồng lên màn đơn để giữ giỏ món, và không hiện trong dialog để
không mất bản nháp.

Xác nhận RECEIPT phát `ingredientChanged()` và `itemChanged(null)`: giá vốn của món
có thể đổi. `MenuItemController` chỉ tải lại khi id là null vì mutation của chính nó
đã cập nhật dòng. Tồn không tính ở client và không đổi `availabilityStatus`.

RECEIPT tăng `version` của món. Form sửa món đang mở khi đó sẽ nhận
`CONCURRENT_MENU_UPDATE` và đi theo đường tải lại hiện có; không tự thử lại.

Event `INVENTORY_LOW_STOCK_ALERT_CHANGED` đọc `itemId`, fallback `ingredientId`.

## File chính

- `lib/core/values/inventory_mode.dart`, `lib/core/values/item_type.dart`
- `lib/features/inventory/data/dto/stock_item_ref_dto.dart`
- `lib/features/menu/presentation/widgets/inventory_mode_selector.dart`
- `lib/features/menu/domain/entities/menu_inputs.dart`
- `lib/features/order/presentation/widgets/order_ingredient_dialog.dart`

## Xác minh

```bash
flutter analyze
```

```bash
flutter test test/features/inventory/direct_stock_data_test.dart test/features/menu/inventory_mode_data_test.dart
```
