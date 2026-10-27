# Áp dụng công thức và cấu hình giá vốn

Đồng bộ Flutter ngày 27/10/2026 theo contract Phase 1/V37 trong backend:
`recipe-application-and-cost-config-api.md` và `recipe-application-and-cost-config-fe-sync.md`.
Chỉ cập nhật Flutter. REST, quyền mutation, tenant từ JWT và realtime contract giữ nguyên.

## Ba trạng thái riêng

| Dữ liệu | Ý nghĩa |
| --- | --- |
| `recipe.active` | Definition là phiên bản hiện hành; không có nghĩa món đang sử dụng công thức |
| `MenuItem.recipeEnabled` | Có yêu cầu áp dụng công thức cho các lần chấp nhận món mới |
| `costConfigured` | Giá tham chiếu thủ công đã được nhập/xác nhận; không suy từ numeric zero |

`MenuItem.costPrice` luôn là giá thủ công/dự phòng. `Ingredient.costPrice` là giá
tham chiếu trên **một baseUnit**. `costPerYieldUnit` của estimate không được ghi vào
hai giá này. Flag trên món không phải kết luận về mức độ đầy đủ giá nguyên liệu.

Private DTO đọc cờ bool từ REST. Constructor defaults dùng cho tương thích code
cũ không thay thế parsing contract; dữ liệu lịch sử snapshot có quy tắc nullable riêng.

## Form và JSON

Form mới để giá vốn trống. Form sửa giữ baseline cùng ý định riêng:
chưa sửa, nhập giá, xác nhận stored zero, hoặc xóa cấu hình. Hiển thị một giá 0
không tự xác nhận nó. Sửa metadata không tự gửi lại giá vốn.

| Ý định | POST | PATCH, kèm `expectedVersion` |
| --- | --- | --- |
| Không nhập/chưa sửa | Bỏ cả hai field | Bỏ cả hai field, server giữ giá/flag |
| Nhập rõ giá, kể cả 0 | Gửi `costPrice` | Gửi `costPrice` |
| Xác nhận giá 0 đang lưu | Cần giá rõ ràng khi tạo | `costConfigured:true`, không cần gửi lại numeric price |
| Xóa cấu hình | Nếu có chủ đích, false với giá bỏ trống/0 | `costConfigured:false`, không gửi giá dương |

Ví dụ xác nhận giá 0:

```json
{"expectedVersion":7,"costConfigured":true}
```

Ví dụ bỏ cấu hình:

```json
{"expectedVersion":7,"costConfigured":false}
```

Xóa nội dung ô nhập trong form sửa không bị diễn giải thành giá 0. Người dùng cần
nhập lại giá hoặc chọn **Xóa cấu hình giá vốn**, xác nhận rồi lưu. **Xác nhận giá 0**
chỉ xuất hiện khi có stored zero chưa được xác nhận. Nhập rõ 0 là một giá đã cấu hình.

Validation chặn POST `costConfigured:true` thiếu giá và tổ hợp false + giá dương.
Input `isEmpty` và serializer giữ flag-only/toggle-only PATCH. `.changes` giữ
costPrice được truyền rõ dù bằng baseline; form chịu trách nhiệm bỏ field chưa sửa.

Giá chưa cấu hình được ghi **Chưa cấu hình giá vốn**, không phải “Miễn phí”. Legacy
zero sau migration cần người có quyền rà soát; app không tự xác nhận hàng loạt.

## Sử dụng công thức

Switch **Sử dụng công thức** có trong form món và chi tiết món, nằm ngoài recipe-only
gate. Món mới off; tạo món/definition trước khi bật. Recipe workspace hiển thị
definition hiện hành và trạng thái áp dụng riêng biệt.

| Action | Capability |
| --- | --- |
| Bật | MENU_UPDATE + menu guards + RECIPE_MANAGEMENT |
| Tắt | MENU_UPDATE + menu guards; không yêu cầu RECIPE_MANAGEMENT |
| Tạo/thay/lưu trữ definition | Quyền recipe tương ứng theo policy hiện có |

Bật không tự yêu cầu RECIPE_UPDATE, inventory hoặc giá nguyên liệu đã cấu hình.
Backend xác minh active recipe/đơn vị và có thể từ chối. Mất feature không tự PATCH
off; người có quyền menu vẫn có thể chủ động tắt.

Luồng **Lưu & sử dụng công thức**:

1. Tạo definition bằng API recipe hiện có.
2. GET MenuItem mới nhất.
3. PATCH menu `recipeEnabled:true` với **MenuItem.version**.
4. Áp dụng response/version, phát MenuCatalogEvents để các reader liên quan cập nhật.

**Lưu công thức** chỉ lưu definition. Recipe lock `version`, business `recipeVersion`
và MenuItem.version là các giá trị khác nhau. Tạo phiên bản thay thế không tự đổi toggle.

Nếu tạo definition thành công nhưng bật thất bại, form báo **Đã lưu công thức, chưa
bật sử dụng**, giữ kết quả đã lưu và cho kiểm tra/bật tiếp theo xác nhận mới. Không
POST definition lại hoặc rollback bằng DELETE. GET xác minh có thể cho biết application
đã bật; khi đó không cần tạo mutation trùng.

Control đọc mới trước PATCH, dùng mutation pipeline/lock của MenuItemController,
chặn double tap và không tăng version ở FE. Sau conflict/unknown outcome cần kiểm tra
lại trước thao tác tiếp. Thay đổi giá vốn/metadata cũng có thể tăng version.

## Lưu trữ definition

Definition active đang được sử dụng cần tắt application trước. UI xác nhận hai ý định,
PATCH menu bằng version menu rồi deactivate recipe bằng version recipe được kiểm tra.
Không dùng version của tài nguyên này cho tài nguyên kia.

Nếu thiếu quyền cập nhật món, không tự tắt. Server vẫn kiểm tra
`RECIPE_APPLICATION_ENABLED`, kể cả khi client không có quyền đọc menu để kiểm tra trước.
Inactive history không bị bắt tắt application của phiên bản hiện hành khác.

Nếu tắt thành công nhưng archive thất bại, báo application đã tắt và definition vẫn
còn; không tự bật lại. Replacement atomic giữ hành vi backend hiện có.

## Estimate

Giữ GET cost-estimate, RECIPE_VIEW + RECIPE_MANAGEMENT, không cần kho. Có thể đọc
definition active/inactive ngay cả khi application off. Estimate dùng giá nguyên liệu
hiện tại, không phải giá vốn lịch sử của phiên bản.

`INGREDIENT_COST_NOT_CONFIGURED` hiển thị hướng dẫn cấu hình giá nguyên liệu.
Action mở danh mục nguyên liệu chỉ có khi đủ quyền đọc và có router; không dựng
ingredient ID bị thiếu nếu response không cung cấp. Không gọi inventory để vượt quyền.

Không fallback về manual backup, không bỏ nguyên liệu thiếu giá hoặc tạo estimate 0.
Configured zero vẫn được tính, kèm ZERO_INGREDIENT_REFERENCE_COST theo contract.

UI tách **Giá bán hiện tại**, **Giá vốn tham chiếu thủ công/dự phòng**, **Giá vốn ước
tính**. Kết quả cũ có thể được giữ với nhãn; khi stale/loading/error thì ngừng trình
bày chênh lệch và tỷ lệ như kết quả hiện tại. Giữ kiểm tra đơn vị/currency và số học
chính xác đang có. Không bổ sung báo cáo lợi nhuận hoặc số tiền giá vốn lịch sử.

## Quyết định lịch sử

Protected recipe snapshot bổ sung:

- `recipeEnabledSnapshot: bool?`.
- `costSourceSnapshot: MANUAL | RECIPE | null`.

| Quyết định tại acceptance | Status | Source | Allocation |
| --- | --- | --- | --- |
| Tắt application | RECIPE_DISABLED | MANUAL | SKIPPED / SNAPSHOT_RECIPE_DISABLED |
| Bật, có feature và recipe hợp lệ | CAPTURED | RECIPE | Theo tracked ingredient policy |
| Bật nhưng thiếu feature | FEATURE_DISABLED | RECIPE | Bỏ qua theo quyết định đã chốt, không fallback thủ công |
| Bật, có feature, thiếu active recipe | 409 ACTIVE_RECIPE_REQUIRED | Chưa có quyết định mới | Không có reservation mới |

RECIPE_DISABLED là quyết định đã persist, có capturedAt. NOT_SUBMITTED chưa chốt.
Legacy fields thiếu/null giữ null; tiếp tục đọc NO_RECIPE và các trạng thái cũ.
Enum allocation phân biệt application-disabled với feature-disabled.

Giỏ/DRAFT/guest QR PENDING/review chưa freeze. Create SUBMIT, confirm, accepted append
và approve QR mới chốt. Dòng cũ giữ snapshot/reservation/cancel/release/consume gốc sau
toggle; hai dòng cùng món có thể khác quyết định. Không thêm config vào request order/QR
hoặc tạo local stock adjustment.

Inspector có nhãn nguồn đã chốt hoặc **Dữ liệu lịch sử chưa ghi nhận nguồn**. MANUAL
không có nghĩa đã chốt một số tiền. Snapshot vẫn cần ORDER_VIEW + RECIPE_VIEW cùng
features tương ứng; allocation thêm quyền/feature kho. Giữ lazy load, scope/generation.
Không đưa metadata giá vốn/quyết định riêng tư vào public QR, KDS hoặc ORDER_CHANGED.

## Nhập kho

Sau receipt CONFIRMED hoặc xác minh confirmed response, composition phát
`MenuCatalogEvents.ingredientChanged()` để reader hợp quyền đối soát giá/flag qua REST.
Không phát từ GET thông thường hoặc ISSUE/ADJUSTMENT; không đọc chi tiết mọi nguyên
liệu trong nền. Ingredient list/selector/estimate đang liên quan nhận tín hiệu.

Tồn đầu dương với giá chưa cấu hình vẫn có thể receipt thành công và tiếp tục chưa
cấu hình. Không giả tồn đầu giá 0, tính bình quân hay tự đặt configured=true ở FE.
`UNCONFIGURED_OPENING_REFERENCE_COST` là reason trong audit
`INGREDIENT_COST_RECALCULATION_SKIPPED`, không phải response warning được cam kết.
Không dựng API/field audit; chỉ phản ánh giá/flag đọc được qua API đã có.

## Cấu trúc triển khai

- Domain/data menu: entity flags, optional input fields, serializers, validation.
- `ReferenceCostField`: nhập giá và intent; form giữ baseline/expectedVersion.
- `RecipeApplicationController` và provider: menu-scoped orchestration, mutation qua
  MenuItemController; RecipeController vẫn sở hữu definition.
- RecipeCostPanel: giữ ba nguồn/ý nghĩa giá riêng, không tính so sánh từ estimate cũ.
- Snapshot DTO/domain/inspector: metadata nullable và trạng thái mới, giữ validation cũ.
- Stock controllers/providers: callback refresh sau receipt, không sửa nghiệp vụ kho.
- Menu/ingredient/recipe access recovery dùng revalidateAccess để giữ bản nháp khi
  kiểm tra quyền không làm thay đổi scope; thay tenant/authority vẫn được fence.

Không có endpoint, package, socket, realtime event hay state management mới.

## Kiểm thử thủ công

1. Tạo món/nguyên liệu để trống giá: phải chưa cấu hình; sửa tên không xác nhận giá 0.
2. Nhập 0 và lưu: đã cấu hình. Với stored zero legacy, dùng **Xác nhận giá 0**.
3. Xóa cấu hình, hủy dialog rồi thử lại/xác nhận; chỉ lưu mới gửi false.
4. Lưu definition rồi xem món vẫn off. Dùng **Lưu & sử dụng** để bật qua bước PATCH.
5. Gây conflict hoặc mất mạng ở bước bật: definition còn, không bị tạo lại.
6. Tắt application và xem definition/history còn nguyên. Thử archive với/không quyền menu.
7. Sau downgrade recipe feature, vào chi tiết/sửa món qua menu và tắt application.
8. Nguyên liệu thiếu giá làm estimate lỗi; manual backup không thay thế. Xác nhận zero
   hoặc cấu hình giá rồi làm mới; estimate hợp lệ lại được so với giá bán.
9. Chấp nhận một dòng, đổi toggle rồi gọi thêm cùng món: inspector từng dòng phản ánh
   quyết định của chính dòng đó, không lấy toggle hiện tại để sửa lịch sử.
10. Receipt trên nguyên liệu có tồn đầu dương/chưa có giá: chứng từ vẫn thành công,
    danh mục đọc lại giá/flag thật; không giả warning riêng hoặc tạo adjustment.
11. Đổi tenant/logout khi GET/POST đang chạy; không có response/callback cũ cập nhật
    scope mới. Kiểm tra form 320–1200 px, text 200%, bàn phím mở và tên/số tiền dài.

## Kiểm tra tự động

Các test mới gồm request matrix, form intent, estimate không fallback/stale, application
workflow, snapshot/allocation lịch sử và receipt refresh. Chạy format file thay đổi,
flutter analyze, test liên quan rồi toàn bộ flutter test. Các assertion cũ về blank→0
được đổi theo contract V37; nhãn definition đổi sang **Phiên bản hiện hành**. Không
giảm assertion khác, bỏ test hoặc update golden để che hồi quy.
