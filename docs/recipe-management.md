# Bàn giao công thức — 16/10/2026

## Truy cập và phạm vi

Trong Thực đơn → Món bán, mở menu thao tác **Công thức**, hoặc nút cùng tên ở chi tiết món. Route `/app/menu/items/{menuItemId}/recipes` mở màn riêng gồm Đang áp dụng và Lịch sử. Công thức chỉ thuộc món đã có ID, không phải ItemType, không nằm trong metadata hoặc payload tạo/sửa món.

Recipe là aggregate riêng trong feature menu: món bán → phiên bản công thức → dòng định lượng → nguyên liệu. Không đưa recipe/ingredient vào danh sách chọn món POS/public/QR. Không bổ sung trừ kho, định lượng thực xuất, quy đổi đơn vị, tự tính giá vốn, backend draft/approval, combo/topping hoặc snapshot vào order.

## Kiến trúc

| Lớp | Thành phần |
| --- | --- |
| Domain | Recipe/RecipeIngredient/RecipeSummary, RecipeQuantity/RecipeWastePercent, typed inputs/query/validation, repository và 6 use case |
| Data | RecipeRemoteDataSource dùng authenticated Dio, DTO/serializer riêng và RecipeRepositoryImpl |
| Presentation | RecipeController/provider theo menuItemId/scope, selector nguyên liệu độc lập, màn active/history, form và scope/dialog guard riêng |
| Tích hợp | AccessPolicy, route, AppShell contextual child, thao tác món/chi tiết, ApiErrorMapper và MenuCatalogEvents |

Không thêm dependency. Domain không biết Flutter/Riverpod/Dio. Widget không gọi HTTP. Các thành phần menu/ingredient hiện có được giữ nguyên; selector công thức dùng repository/use case nguyên liệu nhưng không thay state/filter của màn quản trị.

## API và version

Prefix `/api/v1/menu/items/{menuItemId}/recipes`. Tenant lấy từ JWT; không gửi restaurantId. Response Recipe/page trực tiếp.

| Method | Path tương đối | Quyền | Kết quả |
| --- | --- | --- | --- |
| GET | `/active` | RECIPE_VIEW | Recipe hoặc ACTIVE_RECIPE_NOT_FOUND |
| GET | prefix + query page/size/sortBy/direction | RECIPE_VIEW | Page RecipeSummary |
| GET | `/{recipeId}` | RECIPE_VIEW | Recipe snapshot |
| POST | prefix | RECIPE_CREATE | 201 Recipe |
| POST | `/{activeRecipeId}/versions` | RECIPE_UPDATE | 201 Recipe mới |
| DELETE | `/{recipeId}?expectedVersion=n` | RECIPE_DELETE | 204, không body |

`recipeVersion` là nhãn nghiệp vụ (Phiên bản 1, 2...). `version` là optimistic lock, phải dùng làm expectedVersion. Không tự cộng số, lấy version lịch sử thay baseline active hoặc gửi PATCH/PUT.

POST đầu tiên chỉ gửi yieldQuantity và ingredients. POST version thêm expectedVersion của active baseline. Dòng gửi ingredientId, quantity, wastePercent; không gửi tên/SKU/unit snapshot, ID dòng, yieldUnit, recipeVersion hoặc active. Backend snapshot đơn vị món và nguyên liệu.

History page gồm content/page/size/totalElements/totalPages, summary có ingredientCount và không có ingredients. Sort chỉ recipeVersion/createdAt/updatedAt, mặc định recipeVersion desc; size 1–100, mặc định 20. Không tải detail mỗi dòng để đếm nguyên liệu.

## Định lượng và giao diện

Quantity/yield dùng số nguyên scale 3, >0 và tối đa 999999999.999. Waste percent dùng scale 2, 0–100, mặc định 0. Không dùng MenuPrice scale 2 cho quantity, không validation/so sánh bằng double, không tự làm tròn hoặc quy đổi. Công thức có 1–100 dòng, không trùng ingredientId. trackInventory=false vẫn hợp lệ; món inactive/OUT_OF_STOCK vẫn có thể có công thức.

Form giải thích sản lượng của cả công thức: “Định lượng bên dưới dùng để tạo ra 10 tô”. Mỗi dòng có quantity cho cả công thức, unit chỉ đọc và hao hụt %. Bỏ dòng chỉ xóa bản nháp, không xóa nguyên liệu. Danh sách/field dùng key ổn định, bản nháp không bị response nền ghi đè. Chỉ đổi thứ tự hoặc chuẩn hóa chữ số không tạo version mới.

Màn hẹp dùng card, vùng rộng sắp field thành hàng phù hợp. Có cuộn khi bàn phím mở, vùng nhấn/icon có tooltip, không khóa text scaling hoặc cố định chiều cao nội dung. Picker debounce và phân trang server, active=true, không lọc trackInventory; giữ lựa chọn qua tìm kiếm/trang.

## Snapshot và dùng lại lịch sử

Màn đọc dùng snapshot nguyên bản, không lấy danh mục live thay tên/đơn vị lịch sử. Dùng lại lịch sử chỉ tạo bản nháp; không kích hoạt lại bản cũ. Có active thì dùng ID/version của active làm baseline; không active thì POST đầu tiên không có expectedVersion.

Đối chiếu danh mục hiện tại trước khi dùng lại lịch sử. Nguyên liệu inactive/xóa cần thay/bỏ. Đổi g sang kg phải nhập lại định lượng; không giữ số cũ dưới đơn vị mới. Đổi đơn vị món phải xem lại yield. Thiếu quyền/dữ liệu để xác minh thì giữ màn xem lịch sử, không gửi bản sao dựa trên giả định.

## Quyền và lifecycle

Recipe yêu cầu RECIPE_MANAGEMENT, subscription ACTIVE, tenant và role app hợp lệ, đúng RECIPE_VIEW/CREATE/UPDATE/DELETE trong session. INVENTORY_MANAGEMENT đơn lẻ không đủ. Không bypass cho OWNER; SUPER_ADMIN/CASHIER giữ luồng web-only.

RECIPE_VIEW đủ đọc snapshot từ menuItemId đã biết; không suy ra MENU_VIEW hoặc INGREDIENT_VIEW. MENU_VIEW chỉ dùng khi đọc danh mục món, INGREDIENT_VIEW khi tìm/đối chiếu danh mục nguyên liệu. Route contextual có thể render khi sidebar không có danh mục nào; không thêm sidebar recipe toàn nhà hàng hoặc bịa API list món. Route không giữ MenuItem extra để tránh metadata của tenant cũ sau đổi phiên.

recipeScope theo user/tenant/role/quyền/feature/subscription, không gồm token. Xoay token cùng scope giữ draft/query. Đổi scope/logout hủy nội dung cũ và bỏ response trễ. Form/guard recipe kiểm tra canRecipe riêng, không dùng canMenu/canIngredient. Access recovery giới hạn theo scope, không tạo vòng lặp restore.

Sự kiện recipe có menuItemId riêng; không phát itemChanged giả. Tạo version cập nhật active từ response và refresh history liên quan. DELETE là deactivate; sau 204 phải đọc lại active/history, vì retry recipe inactive cũ không được làm mất active mới.

## Xung đột và guard

Chỉ ACTIVE_RECIPE_NOT_FOUND từ GET active là trạng thái chưa có công thức. Các lỗi mạng, thiếu quyền hoặc món không tồn tại vẫn hiển thị lỗi đúng loại.

CONCURRENT_RECIPE_UPDATE/RECIPE_NOT_ACTIVE/ACTIVE_RECIPE_ALREADY_EXISTS giữ draft, yêu cầu tải lại để đối chiếu và xác nhận trước khi thay baseline. Không tự đổi endpoint hoặc gửi lại bằng version mới. SAME_RECIPE_VERSION_NOT_ALLOWED không được coi là lưu thành công. Timeout báo kết quả chưa xác định, không tự tạo thêm version.

ApiErrorMapper thêm thông báo Việt cho recipe và các guard:

- MENU_ITEM_UNIT_IN_USE: gắn lỗi vào baseUnit của món.
- INGREDIENT_UNIT_IN_USE: gắn lỗi vào baseUnit nguyên liệu.
- MENU_ITEM_HAS_ACTIVE_RECIPE: chưa thể xóa món.
- INGREDIENT_USED_BY_ACTIVE_RECIPE: chưa thể disable/xóa nguyên liệu.

Giữ các nội dung khác đang sửa, không tự ngừng công thức để vượt guard. Khi chỉ còn lịch sử inactive, không khóa vĩnh viễn khả năng đổi unit/soft-delete; backend quyết định trạng thái mới nhất.

## Kiểm tra

Các test recipe kiểm tra đủ sáu endpoint, số thập phân/normalization, expectedVersion, snapshot và summary, quyền đọc độc lập, stale request/scope, debounce/picker, deactivate retry, no-op, form/draft/conflict/history clone và layout 320/800/1200 với chữ 200%, bàn phím mở. Test tích hợp kiểm tra route recipe-only, entry menu chỉ tải khi mở và unit guard tại form hiện có.

Chạy `flutter analyze`, test recipe/menu/ingredient và hồi quy toàn dự án. Test HTTP dùng fake repository hoặc Dio interceptor, không thao tác dữ liệu nhà hàng thật. Chưa xác nhận end-to-end với backend/thiết bị thật trong phiên triển khai.

Kết quả thực tế ngày 16/10/2026 (Flutter 3.32.1 / Dart 3.8.1):

- Formatter: 25 file recipe, không còn thay đổi định dạng.
- `flutter analyze --no-pub`: **No issues found**, 18,5 giây.
- `flutter test --no-pub --reporter expanded`: **449/449 test đạt**, 67 giây; gồm 55 test recipe (9 domain/data, 26 controller/provider/selector, 14 widget và 6 tích hợp) cùng hồi quy các module hiện có.
- Hai regression bổ sung kiểm tra response active cũ sau conflict không mở khóa ghi và đơn vị món/nguyên liệu đổi trong lúc tạo công thức phải nhập lại lượng dùng.

Chưa build lại APK hoặc xác nhận thao tác với backend/thiết bị thật. Không thêm dependency hay thay đổi backend.
