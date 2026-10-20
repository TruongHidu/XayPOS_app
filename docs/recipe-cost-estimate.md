# Ước tính giá vốn công thức — 19/10/2026

Trong Thực đơn → Công thức → Đang áp dụng, panel **Giá bán & giá vốn** nằm sau thông tin phiên bản/sản lượng. Chi tiết lịch sử dùng cùng panel, gọi đúng recipeId đã mở. Danh sách lịch sử chỉ đọc summary, không tải estimate mỗi dòng. Công thức chưa lưu và món chưa có công thức không có estimate giả.

## Luồng và vị trí mã nguồn

`RecipeDetails → RecipeCostPanel → RecipeCostController/provider → GetRecipeCostEstimate → RecipeRepository.costEstimate → RecipeRepositoryImpl → RecipeRemoteDataSource → GET cost-estimate`.

- Domain: `recipe_cost_estimate.dart`, `recipe_cost_amount.dart`, `recipe_cost_comparison.dart`; entity bất biến, tiền/decimal dùng BigInt, không biết Flutter/Dio/Riverpod.
- Data: `recipe_cost_estimate_dto.dart`; endpoint bổ sung trong remote/repository recipe hiện có. `core/network/exact_json.dart` giữ token số nguyên bản trước khi parse, không phụ thuộc inventory.
- Presentation: `recipe_cost_controller.dart`, `recipe_providers.dart`, `recipe_cost_panel.dart`, `recipe_cost_format.dart`. Provider autoDispose theo menuItemId/recipeId/scope. Panel đóng thì bỏ estimate, mở lại GET mới.
- `RecipeMenuPriceController` dùng chung cho header màn công thức và panel active/history, đọc `GetMenuItemDetail` một lần khi mở workspace. Nút cập nhật tải lại giá bán và estimate với trạng thái lỗi độc lập. Dữ liệu menu extra ban đầu không được xem là giá bán mới nhất.

Không đổi backend, dependency, route, quyền ghi hoặc payload tạo/sửa recipe.

## Contract đọc

`GET /api/v1/menu/items/{menuItemId}/recipes/{recipeId}/cost-estimate`, authenticated Dio, Accept application/json, no-store. Không body/query, expectedVersion, idempotency key, restaurantId hoặc warehouseId. Yêu cầu RECIPE_VIEW + RECIPE_MANAGEMENT; không cần kho, tồn kho, INVENTORY_VIEW, INGREDIENT_VIEW. Không chặn món inactive/OUT_OF_STOCK hoặc recipe inactive.

Chỉ đọc giá bán nếu có MENU_VIEW theo AccessPolicy. Thiếu quyền/lỗi giá bán vẫn xem được estimate và snapshot. menuItemId/recipeId trong response phải khớp request; dữ liệu thiếu/null/sai không tự thành 0.

`recipeVersion` là phiên bản nghiệp vụ. `recipeActive` là trạng thái tại lúc ước tính; không cập nhật baseline optimistic lock dựa trên estimate.

## Nguồn giá và đơn vị

Giá vốn một đơn vị sản lượng dùng `costPerYieldUnit`; tổng mẻ dùng `totalBatchCost`. Tên/SKU/unit/định lượng/waste/yield là snapshot đúng phiên bản. `unitCost` là giá ingredient hiện tại trên một baseUnit. Không thay bằng giá kho, không GET từng nguyên liệu, không bỏ trackInventory=false/inactive/deleted còn nguồn giá.

Giá bán lấy `MenuItem.salePrice`, không lấy `MenuItem.costPrice`. Trong backend hiện tại, menu salePrice thuộc tiền tệ nhà hàng (menu không có tiền tệ riêng); estimate trả currencyCode nhà hàng của cùng JWT tenant. Panel gắn currencyCode đó cho giá bán chỉ khi estimate hợp lệ và menuItemId/scope cùng hiện tại. Policy so sánh nhận currency riêng và từ chối thiếu/khác currency; nếu backend sau này hỗ trợ nhiều tiền tệ trên menu item phải truyền currency thực tế và tiếp tục chặn khác currency.

Chỉ so sánh nếu unit bán khớp yieldUnit (trim, không quy đổi tên/đơn vị). Chênh lệch = salePrice − costPerYieldUnit, tỷ lệ = costPerYieldUnit / salePrice × 100%, HALF_UP một số lẻ bằng BigInt. SalePrice=0 hiển thị tỷ lệ “Không áp dụng”. Chênh lệch âm có cảnh báo. Không gọi đây là lợi nhuận ròng; chưa bao gồm nhân công, vận hành, thuế, phí và chi phí khác.

Ví dụ yield=10 tô, total=369.000 VND, per-yield=36.900 VND, sale=60.000 VND/tô → chênh lệch=23.100 VND, tỷ lệ=61,5%.

Không tự tính lại lineCost/total/per-yield thay backend. Decimal gross không bị giới hạn scale 3: `0.0010001` hiển thị đầy đủ. Tiền giữ đến cent, tổng lớn dùng BigInt không ép giới hạn MenuPrice. ResponseType.plain + generic dynamic ngăn Dio transform số qua double. estimatedAt hiển thị giờ địa phương. Locale hiển thị nhóm nghìn dấu chấm, phần lẻ dấu phẩy và luôn ghi mã tiền tệ từ API.

## Vòng đời, lỗi và giao diện

- Request đầu tự tải một lần, rebuild không gọi thêm. Cập nhật chặn double tap, hai nguồn tải song song. Không polling/auto retry.
- Scope giữ qua token refresh, thay đổi user/tenant/quyền/feature/subscription thì bỏ dữ liệu và response trễ. Generation ngăn request cũ ghi đè sau catalog event. Khởi tạo load qua microtask, không ghi state trong build.
- Ingredient event liên quan và recipe event của món đánh dấu estimate cũ; item event đánh dấu giá bán cũ. Không phát event recipe giả khi đọc. Bấm cập nhật để lấy giá mới.
- Refresh lỗi giữ estimate cũ với nhãn “Kết quả lần tải trước” và estimatedAt. Lỗi giá bán không làm mất estimate; lỗi estimate không làm mất snapshot công thức.
- 409 `INGREDIENT_COST_UNIT_MISMATCH`, `INGREDIENT_COST_UNAVAILABLE`, `INVALID_INGREDIENT_REFERENCE_COST`, `INVALID_RECIPE_COST_DATA` có thông báo Việt riêng; không bỏ dòng lỗi, tự quy đổi hoặc gán 0. 400/401/403/404 đi qua cơ chế Failure hiện có.
- Giá tham chiếu bằng 0 hợp lệ, warning theo ingredientId/code được loại trùng, banner và dấu cảnh báo ở dòng. Toàn bộ giá 0 vẫn là kết quả thành công.
- Card giá bán/giá vốn/chênh lệch/tỷ lệ luôn hiện. Chi phí từng nguyên liệu thu gọn riêng, desktop dạng bảng, mobile dạng card. PageStorageKey của breakdown và scroll khác nhau, không ghi đè bool/double. Nút tối thiểu 48px, hỗ trợ chữ 200%, nội dung dài xuống dòng.

## Kiểm tra

Các test `recipe_cost_data_test.dart`, `recipe_cost_controller_test.dart`, `recipe_cost_widget_test.dart` kiểm tra wire contract, Dio transformer thật qua fake adapter, decimal/exponent/tổng lớn, warning/zero/null, errors, request generation, shared menu read, scope/token, dữ liệu lịch sử, các phép so sánh và responsive 320/600/800/1200/1440 ở chữ 100%/200%.

`tool/verify_recipe_cost_precision.dart` là probe Dart thuần để compile JavaScript và chạy Node, kiểm tra BigInt/JSON không mất độ chính xác trên web.

Kết quả ngày 19/10/2026:

- `flutter test --reporter expanded`: **664/664 test đạt**, gồm **26 test mới** cho ước tính giá vốn (6 data/domain, 4 controller, 16 widget).
- `dart analyze`: **No issues found**.
- Probe Dart compile JavaScript chạy bằng Node: đạt, giữ nguyên tổng `999999999999999999.99` và gross `0.0010001`.
- Đã render và xem ảnh 1440/600/320 px; helper chụp ảnh tạm đã được xóa, ảnh lưu trong build (ignored).

Không gọi mutation trên backend thật. Chưa xác nhận end-to-end với backend/thiết bị thật.
