# Hệ thống giao diện (design system)

Mọi màn hình lấy màu, cỡ chữ, khoảng cách, bo góc và component từ một chỗ, để
app trông giống nhau ở mọi nơi và đổi giao diện (kể cả dark mode sau này) chỉ cần
sửa theme. Thiết bị chính: **điện thoại Android** (phục vụ, thu ngân) và
**tablet/màn POS** (thu ngân, bếp).

Phong cách: giữ xanh thương hiệu `#0863BE`, nền trang xám nhạt `#F4F6F8`, card
trắng viền mảnh, gần như không có bóng đổ. Font **Be Vietnam Pro** đóng gói trong
`assets/fonts/BeVietnamPro/` (giấy phép OFL).

## Token (`lib/app/theme`)

| File | Nội dung |
| --- | --- |
| `app_colors.dart` | `AppColors`: màu thương hiệu, xám, trạng thái, tiền, accent. Chỉ file này được viết mã màu. |
| `app_status_colors.dart` | `AppTone` (neutral, primary, success, warning, danger, info, orange, cyan, violet, indigo) và `ThemeExtension` `AppStatusColors`. Lấy màu: `context.tone(AppTone.success)` → `foreground`/`background`/`border`. |
| `app_tokens.dart` | `AppSpacing` (4/8/12/16/20/24/32, `pageGutter`), `AppRadius` (`xsAll` 4, `smAll` 8, `buttonAll` 10, `mdAll` 12, `lgAll` 16, `xlAll` 20, `pillAll`), `AppBreakpoints`, `AppDurations`. |
| `app_typography.dart` | Thang chữ Material 3 với tiêu đề/nhãn đậm hơn; `textTheme.money`, `moneyLarge` (chữ số thẳng cột), `caption`. |
| `app_theme.dart` | `AppTheme.light`: color scheme ghim màu xám trung tính, và theme cho AppBar, card, ô nhập, nút, chip, tab, dialog, bottom sheet, snackbar, bảng, tooltip, rail, badge. |

Ánh xạ màu xám sang vai trò của `colorScheme` (dùng cái bên phải khi viết mới):

| Thay vì | Dùng |
| --- | --- |
| `grey900`, `grey800` | `onSurface` |
| `grey600`, `grey500` | `onSurfaceVariant` |
| `grey400` | `outline` |
| `grey300`, `grey200` | `outlineVariant` |
| `grey100`, `grey50` | `surfaceContainer`, `surfaceContainerLow` |
| `Colors.white` (nền) | `surface` |

## Component dùng chung (`lib/core/ui/widgets`)

| Component | Dùng cho |
| --- | --- |
| `StatusBadge` | Nhãn trạng thái theo tone, có icon hoặc chấm. Feature chỉ ánh xạ trạng thái của mình sang `AppTone` (ví dụ `KitchenStyle.tone`, `marginCoverageTone`). |
| `SectionHeader` | Tiêu đề nhóm: `regular` (trang/card), `small` (dialog), `label` (nhóm trường, bộ lọc). Nút bên phải tự xuống dòng khi hẹp. |
| `AppSectionCard` | Card trắng viền mảnh có tiêu đề tùy chọn; `compact` cho trong dialog. |
| `StatTile` | Số liệu KPI: nhãn, giá trị, gợi ý, icon theo tone/màu, tooltip. `ReportKpiCard` bọc lại nó. |
| `MoneyText` | Số tiền theo `formatMoney`, chữ số thẳng cột. |
| `EmptyState`, `LoadingState`, `ErrorState`, `ErrorBanner`, `RetryButton`, `LoadingStrip`, `ListSkeleton` | Trạng thái rỗng/đang tải/lỗi (`list_states.dart`). |
| `AppSearchField` | Ô tìm kiếm có nút xoá và debounce, cho màn mới. |
| `AppConfirmDialog`, `showAppConfirmDialog` | Câu hỏi có/không; `destructive` tô đỏ nút xác nhận. |
| `ResponsiveColumns` / `ResponsiveSliverColumns` | Lưới card theo bề rộng; bản sliver dựng lười từng hàng cho danh sách dài. |
| `ElapsedText`, `MinuteTickerBuilder` | "45 phút" tự cập nhật bằng một đồng hồ chung (`MinuteClock`). |
| `AppNetworkImage` | Ảnh từ mạng (bắt buộc, có guard test); `opacity` làm mờ rẻ hơn `Opacity`. |

Feature vẫn giữ tên widget riêng khi cần (`InventoryBadge`, `MenuFailurePanel`,
`confirmOrderAction`…), nhưng bên trong chỉ gọi component chung.

## Shell và bố cục

`lib/app/shell/app_shell.dart` là khung chung; màn hình của từng mục sidebar khai
báo ở `shell_sections.dart`, tab theo vai trò ở `shell_tabs.dart` (lớp `app` được
import feature, `core` thì không).

| Bề rộng | Điều hướng |
| --- | --- |
| < 600 (điện thoại) | Bottom tab theo vai trò + "Khác" mở sidebar. AppBar 56. |
| 600–1023 (tablet dọc) | Như điện thoại; AppBar 64; lề trang 24. |
| ≥ 1024 (tablet ngang, POS) | Rail 88px luôn hiện bên trái (icon + nhãn ngắn `shortLabel`, badge); nút menu mở sidebar đầy đủ. |

Màn hình trong shell không tự tạo `Scaffold`/`AppBar`. Đặt khoảng cách và bo góc
bằng token; form giới hạn bề rộng khoảng 720; vùng chạm tối thiểu 48; phải vừa
màn 320px với cỡ chữ 200% (có test).

## Hiệu năng

- **Watch hẹp**: session lấy qua `currentSessionProvider`, không watch cả
  `authControllerProvider`. Phần tử trong danh sách dùng
  `ref.watch(p.select((c) => …))` cho đúng phần mình cần.
- **Giá trị select phải so sánh được**: controller cache danh sách dẫn xuất và
  xoá cache khi `notifyListeners` (xem `KitchenDisplayController`,
  `OrderServiceContextController.tables`, `QrInboxController.forTable`), thay vì
  getter tạo list mới mỗi lần đọc.
- **Giữ provider sống mà không rebuild**: `ref.listen(p, (_, _) {})` thay cho
  `ref.watch(p)` khi chỉ cần provider tồn tại.
- **Danh sách dài dựng lười**: `ResponsiveSliverColumns`/`SliverList.builder`
  trong `CustomScrollView`, các sliver đặt ngang hàng (không gom bằng
  `SliverMainAxisGroup`, để viewport chia cache đúng). `EndlessListFooter` chỉ
  quay spinner khi gần cuối danh sách.
- **Thời gian chạy**: dùng `ElapsedText`/`MinuteTickerBuilder`, không đặt
  `Timer.periodic` + `setState` cho cả màn hay cho từng ô.
- **Vẽ**: `CustomPainter.shouldRepaint` so dữ liệu thật; tránh `Opacity` và
  `BoxShadow` mờ trên từng phần tử danh sách; đọc `MediaQuery.sizeOf`/`paddingOf`
  thay cho `MediaQuery.of`.
- **Lint**: `analysis_options.yaml` bật `prefer_const_*`, `use_colored_box`,
  `use_decorated_box`, `sized_box_for_whitespace`, `avoid_unnecessary_containers`.
  Chạy `dart fix --apply` sau khi sửa nhiều file.

## Guard test

| Test | Kiểm tra |
| --- | --- |
| `test/app/theme/color_tokens_test.dart` | Không có mã màu thô hay `Colors.*` (trừ trắng/đen/trong suốt) ngoài `app_colors.dart`. |
| `test/app/theme/style_tokens_test.dart` | Ratchet: số `fontSize:` cứng, `BorderRadius.circular(số)` và `AppColors.grey*` trong `lib/features` + `lib/core/ui` chỉ được giảm. Khi xoá bớt, hạ trần trong test ở cùng commit. |
| `test/architecture/layer_imports_test.dart` | `lib/core/ui` không import feature; `domain` không import Flutter/Riverpod/Dio. |
| `test/app/theme/app_theme_test.dart` | Màu ghim, card phẳng, tone đăng ký, font khai báo và file font tồn tại. |
| `test/core/ui/network_image_usage_test.dart` | Ảnh mạng chỉ qua `AppNetworkImage`. |

Golden (`test/features/order/goldens`, `test/features/qr_order/goldens`) dựng với
theme mặc định và font test. Khi đổi giao diện lưới bàn, chạy
`flutter test --update-goldens test/features/order/order_widget_test.dart test/features/qr_order/qr_request_widget_test.dart`,
xem lại ảnh rồi mới commit. Thư mục `failures/` đã được bỏ qua trong Git.

## Nên / Không nên

| Nên | Không nên |
| --- | --- |
| `Theme.of(context).textTheme.titleSmall` | `TextStyle(fontSize: 14, fontWeight: …)` |
| `AppRadius.mdAll`, `AppSpacing.lg` | `BorderRadius.circular(12)`, `EdgeInsets.all(13)` |
| `context.tone(AppTone.warning)` | Tự trộn `AppColors.warning` + `withValues(alpha: …)` |
| `StatusBadge`, `SectionHeader`, `ErrorBanner` | Viết lại badge/tiêu đề/khung lỗi trong feature |
| `colorScheme.onSurfaceVariant` | `AppColors.grey600` |
| `ref.watch(p.select(…))` ở widget lá | `ref.watch(controller)` ở đầu một build 500 dòng |
| Sliver dựng lười cho danh sách phân trang | `Wrap`/`Column` chứa toàn bộ phần tử |
