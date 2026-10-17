# Bàn giao quản lý nguyên liệu — 16/10/2026

## Phạm vi

Mở Thực đơn tại `/app/menu`. Workspace có Món bán, Nhóm món và Nguyên liệu; chỉ hiện các tab có quyền xem. Người chỉ có `INGREDIENT_VIEW` vẫn vào được workspace qua sidebar, route và màn home. Quyền truy cập app của CASHIER/SUPER_ADMIN giữ nguyên.

Nút thêm mặc định theo tab đang mở. Khi có quyền tạo cả hai loại, chọn Món bán (`MENU_ITEM`) hoặc Nguyên liệu (`INGREDIENT`). Mỗi loại giữ form và bản nháp riêng trong phiên dialog; chỉ dựng form sau khi chọn lần đầu. Đổi loại không trộn field/payload, không đổi loại lúc đang lưu. Đóng dialog hoặc đổi scope sẽ bỏ bản nháp. Sửa bản ghi dùng form riêng, không đổi itemType.

Không triển khai công thức, định lượng, nhập/xuất kho, tồn thực tế hoặc quy đổi đơn vị. `trackInventory` chỉ là cờ cấu hình. Nguyên liệu không đi vào repository/list món để bán của POS.

## Kiến trúc

Tất cả thuộc feature `menu`:

| Lớp | Thành phần |
| --- | --- |
| Domain | Ingredient, IngredientQuery, typed inputs, IngredientRepository, 6 use case, IngredientValidation; tái sử dụng MenuPrice/MenuPage |
| Data | IngredientDto, IngredientRequests, IngredientRepositoryImpl, 6 method mới của MenuRemoteDataSource |
| Presentation | IngredientController/provider, IngredientList, IngredientForm, chi tiết, confirm dialog và scope guard |
| Chọn loại | ItemType và CatalogItemCreateDialog; MenuItemForm tiếp tục dùng model/request món bán |
| Tích hợp | AccessPolicy, sidebar filter, menu workspace và ApiErrorMapper |

Domain không phụ thuộc Flutter/Riverpod/Dio; widget không gọi HTTP. Dùng authenticated Dio hiện có và cấu hình môi trường của app. Không thêm dependency hoặc gửi restaurantId; backend lấy tenant từ JWT.

## API

Prefix `/api/v1/menu/ingredients`. Response entity/page trực tiếp, không bọc `data`. Ingredient DTO không yêu cầu `itemType`, giá bán, nhóm hoặc ảnh; costPrice và version phải hợp lệ, không tạo dữ liệu giả để biến ingredient thành MenuItem.

| Method | Path | Quyền | Body/query |
| --- | --- | --- | --- |
| GET | prefix | INGREDIENT_VIEW | q, active, trackInventory, page, size, sortBy, direction |
| GET | `/{id}` | INGREDIENT_VIEW | Không body |
| POST | prefix | INGREDIENT_CREATE | name, baseUnit, sku/description tùy chọn, costPrice, trackInventory, active |
| PATCH | `/{id}` | INGREDIENT_UPDATE | Field đổi và expectedVersion; không có active |
| PATCH | `/{id}/status` | INGREDIENT_UPDATE | active và expectedVersion |
| DELETE | `/{id}` | INGREDIENT_DELETE | expectedVersion trong query; không body, nhận 204 |

Query: q tối đa 100 ký tự; size 1–100; sortBy chỉ createdAt/updatedAt/name/sku/costPrice; direction asc/desc. Dio encode query; không thêm wildcard hay field filter món bán.

Tạo mới: SKU trim/uppercase; SKU/mô tả trống bị bỏ khỏi payload. Giá vốn trống là 0, trackInventory mặc định false, active mặc định true. Không gửi itemType/itemGroupId/salePrice/imageUrl/availabilityStatus/metadata.

PATCH: chỉ field đổi, null/bỏ field nghĩa là giữ nguyên; chuỗi rỗng xóa SKU/mô tả. Giá vốn không chạm được bỏ qua; chủ động xóa ô giá vốn gửi số 0. PATCH không có thay đổi không gọi server. Giá dùng MenuPrice lưu 1/100, tối đa 999999999999.99, so sánh/validation không dùng double; chỉ chuyển JSON number tại serializer.

Trạng thái sửa bằng thao tác riêng. Dùng version của bản ghi khi mở/xác nhận. Response server quyết định version; no-op status/update có thể không tăng version. Xóa mềm giữ SKU, không có restore.

## Quyền và lifecycle

`canIngredient` yêu cầu tenant hợp lệ, subscription ACTIVE, permission tương ứng và ít nhất một feature RECIPE_MANAGEMENT/INVENTORY_MANAGEMENT. OWNER không bypass. Controller và UI cùng kiểm tra quyền.

`ingredientScope` dùng cùng ranh giới danh tính/quyền/feature/subscription với menuScope, không gồm token. Token rotation cùng scope giữ query/bản nháp. Đổi tài khoản/tenant/quyền/feature hoặc logout dựng lại controller, đóng form cũ và bỏ response cũ. MenuScopeGuard và IngredientScopeGuard kiểm tra policy riêng.

Controller debounce 350 ms, bỏ response query cũ, khóa mutation theo ID, giữ rows khi refresh, chuyển về trang hợp lệ khi xóa hết trang cuối. Sự kiện nguyên liệu có revision riêng; không phát itemChanged vào luồng món bán. Mutation thành công refresh danh sách một lần.

Lỗi quyền dùng IngredientAccessRecovery, giới hạn một lần restore cho mỗi scope; không lặp request khi bị từ chối. Không tự retry tạo hoặc mutation khi timeout/conflict.

SKU_EXISTS hiện lỗi tại field SKU, kể cả SKU thuộc món bán/bản ghi đã xóa. CONCURRENT_INGREDIENT_UPDATE giữ draft và khóa gửi lại; tải lại chi tiết chỉ thay baseline sau xác nhận bỏ draft. INGREDIENT_NOT_FOUND tải lại danh sách, không fallback sang món bán. Lỗi trạng thái chỉ thông báo/tải lại, không suy đoán chuyển trạng thái ngoài contract.

## Giao diện và kiểm tra

IngredientList chọn bảng theo chiều rộng vùng thực tế và cỡ chữ; vùng hẹp dùng card. Bảng dùng đủ chiều rộng, cuộn ngang nếu nội dung cần thêm chỗ. Filter, tab và chọn itemType xuống dòng; card/form không cố định chiều cao. Hỗ trợ cỡ chữ 200% và bàn phím mở. Form chia Thông tin cơ bản/Giá vốn và theo dõi/Mô tả; active chỉ chỉnh lúc tạo, khi sửa hiển thị trạng thái đọc.

Kiểm thử tự động gồm contract đủ 6 endpoint, PATCH/204/giá/SKU, permission và scope, response cũ, chống submit trùng, xung đột/tải lại baseline, tạo cả hai loại và bản nháp riêng, status/delete xác nhận, các chiều rộng 320/800/1200 với chữ 200%, form khi bàn phím mở. Chạy:

```powershell
flutter analyze
flutter test test/features/menu
```

Kết quả phiên triển khai: `flutter analyze` không phát hiện vấn đề; `flutter test` toàn dự án có **394 test đạt**, gồm hồi quy món bán, tạo đơn, xác thực, điều hướng và nguyên liệu.

Kiểm tra với backend thật: dùng tài khoản có một trong hai feature và quyền nguyên liệu; thử tạo, sửa, lọc, bật/tắt, xóa; mở cùng nguyên liệu trên hai thiết bị để kiểm tra version; thử tài khoản chỉ có quyền xem. Bản triển khai được kiểm tra bằng fake repository/Dio interceptor; chưa xác nhận end-to-end với backend hoặc thiết bị thật.
