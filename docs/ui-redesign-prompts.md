# Bộ prompt thiết kế lại giao diện Xây POS

Mục tiêu: cải thiện trải nghiệm người dùng (UX) trên **điện thoại Android** (phục
vụ, thu ngân) và **tablet/màn POS** (thu ngân, bếp) mà **không đổi nghiệp vụ**:
quyền, luồng API, idempotency/version, xác nhận, tiền tệ và thứ tự thao tác giữ
nguyên. Đọc cùng [hệ thống giao diện](ui-design-system.md).

## 0. Có dùng Claude Design được không?

Được, nhưng đúng vai:

| Công cụ | Làm gì | Không làm gì |
| --- | --- | --- |
| **Claude Design** (claude.ai) | Thử nhiều phương án bố cục, dựng mockup/prototype bấm thử được cho từng màn, chốt hướng thiết kế; dựng design system từ file bạn đưa vào; xuất bản bàn giao (handoff) cho Claude Code. | Không sửa code Flutter của bạn; kết quả là HTML/hình ảnh, không biết quyền, API hay test trong repo. |
| **Claude Code** (trong repo này) | Hiện thực thiết kế đã chốt bằng Flutter, dùng token và component sẵn có, giữ nguyên controller/use case, chạy test và guard test. | Không tự nghĩ thêm tính năng/nghiệp vụ mới. |

Quy trình đề xuất cho **mỗi màn** (làm từng màn một, một màn một commit):

1. **Chụp màn hiện tại** trên điện thoại (khoảng 360×800) và tablet ngang
   (1280×800), gồm các trạng thái: có dữ liệu, rỗng, đang tải, lỗi, không có quyền.
2. **Claude Design**: dán *Prompt nền* (mục 1, một lần cho cả dự án), rồi dán
   *prompt màn* ở mục 3 kèm ảnh chụp. Yêu cầu 2–3 phương án, chọn một, chỉnh tiếp.
3. **Xuất bàn giao**: dùng chức năng handoff sang Claude Code nếu có, hoặc xuất
   ảnh từng frame + ghi chú tương tác, lưu vào `docs/design/<ten-man>/`.
4. **Claude Code**: dán *Khung prompt triển khai* (mục 2) đã điền phần riêng của
   màn (mục 3), đính kèm ảnh/handoff.
5. **Nghiệm thu** theo checklist ở mục 4, chạy trên máy thật với tài khoản từng vai
   trò (chủ quán, quản lý, nhân viên phục vụ, bếp).

Thứ tự ưu tiên (theo tần suất dùng): Shell → Gọi món (sơ đồ bàn) → Chọn món →
Chi tiết đơn & thanh toán → Màn hình bếp → Đơn hàng / Mang đi → Tổng quan →
Báo cáo → Sổ quỹ → Thực đơn → Bàn → Kho → Nhân viên → Cài đặt → Đăng nhập.

Lưu ý khi đưa file lên Claude Design: chỉ đưa `docs/ui-design-system.md`,
`lib/app/theme/*.dart` và ảnh chụp màn hình. **Không** đưa `.env`, khóa, dữ liệu
khách hàng thật hay ảnh có số tài khoản thật.

---

## 1. Prompt nền cho Claude Design (dán một lần)

```text
Bạn là product designer cho "Xây POS" — app POS SaaS cho nhà hàng/quán ăn Việt Nam,
viết bằng Flutter (Material 3). Toàn bộ chữ trên giao diện là tiếng Việt.

NGƯỜI DÙNG VÀ THIẾT BỊ
- Nhân viên phục vụ, thu ngân: điện thoại Android cầm tay (360×800), thao tác một tay,
  vừa đi vừa bấm, giờ cao điểm rất đông.
- Thu ngân tại quầy: tablet ngang / màn POS (1280×800), chạm bằng ngón tay.
- Bếp: tablet ngang đặt cách người đọc 1–2 m (màn hình bếp – KDS).
- Chủ quán, quản lý: điện thoại và tablet, xem tổng quan, báo cáo, quản trị.
Không thiết kế cho chuột/hover: mọi thao tác phải làm được bằng chạm, vùng chạm ≥ 48dp.

PHONG CÁCH (giữ nguyên, chỉ tinh chỉnh)
- Màu thương hiệu xanh #0863BE. Nền trang xám nhạt #F4F6F8, card trắng viền mảnh
  1px, gần như không đổ bóng, bo góc 12–16. Nút bo 10.
- Font Be Vietnam Pro. Số tiền dùng chữ số thẳng cột (tabular), định dạng
  "125.000 ₫".
- Màu trạng thái theo tone: neutral, primary, success, warning, danger, info,
  orange, cyan, violet, indigo — mỗi tone có cặp chữ/nền/viền nhạt. Trạng thái luôn
  có chữ hoặc icon đi kèm, không chỉ dựa vào màu.
- Khoảng cách theo bước 4/8/12/16/20/24/32. Lề trang 16 (điện thoại), 24 (tablet).
- Chỉ làm giao diện sáng, nhưng chọn màu theo vai trò (nền, chữ chính, chữ phụ,
  viền) để sau này có thể làm giao diện tối.

ĐIỀU HƯỚNG (giữ cấu trúc)
- < 600dp: thanh tab dưới theo vai trò (tối đa 4 mục) + "Khác" mở menu đầy đủ.
  AppBar cao 56.
- ≥ 1024dp: rail trái 88px luôn hiện (icon + nhãn ngắn + badge), nút menu mở
  sidebar đầy đủ.
- Tab theo vai trò: Bếp = [Màn hình bếp, Đơn hàng]; Chủ quán/Quản lý = [Tổng quan,
  Gọi món, Đơn hàng, Báo cáo]; Nhân viên = [Gọi món, Đơn hàng, Mang đi, Bàn].

COMPONENT CÓ SẴN (ưu tiên dùng lại, chỉ đề xuất component mới khi thật cần)
StatusBadge (nhãn trạng thái theo tone), SectionHeader, AppSectionCard, StatTile
(KPI), MoneyText, EmptyState / LoadingState / ErrorState / ErrorBanner / ListSkeleton,
AppSearchField, AppConfirmDialog (có kiểu nguy hiểm màu đỏ), lưới card co giãn theo
bề rộng, ElapsedText ("45 phút" tự cập nhật), bottom sheet và dialog Material 3.

RÀNG BUỘC KỸ THUẬT (để thiết kế làm được bằng Flutter, chạy mượt trên Android tầm trung)
- Không dùng blur/glassmorphism, gradient lớn, bóng mờ trên từng phần tử danh sách,
  animation dài. Chuyển cảnh ≤ 250ms.
- Danh sách dài cuộn lười, phân trang vô hạn; không thiết kế thứ cần tải hết dữ liệu.
- Phải vừa màn 320dp với cỡ chữ hệ thống 200%: chữ xuống dòng, không cắt số tiền.
- Mỗi màn có đủ trạng thái: đang tải (skeleton), rỗng, lỗi + Thử lại, dữ liệu cũ /
  chưa đồng bộ, không có quyền, đang gửi (nút khóa + spinner).

NGHIỆP VỤ LÀ BẤT BIẾN
Bạn chỉ thiết kế lại cách trình bày và luồng thao tác trên màn. Không thêm/bớt
nghiệp vụ, không bỏ bước xác nhận, không đổi ý nghĩa nút, không tự tính số liệu
mà hệ thống không có. Nếu thấy nghiệp vụ hiện tại gây khó dùng, ghi vào mục
"Đề xuất cần duyệt" riêng, không đưa vào thiết kế chính.

KẾT QUẢ MỖI MÀN
- Frame điện thoại 360×800 và tablet ngang 1280×800.
- Các trạng thái nêu trên.
- Ghi chú tương tác: chạm vào đâu mở gì, dialog/sheet nào, nút nào khóa khi nào.
- Danh sách thay đổi so với ảnh chụp hiện tại và lý do UX (ngắn gọn).
```

---

## 2. Khung prompt triển khai cho Claude Code

Điền các chỗ `<…>` bằng phần riêng của màn ở mục 3, rồi dán vào Claude Code.

```text
Hiện thực thiết kế mới cho màn <TÊN MÀN> trong app Flutter Xây POS.
Thiết kế đính kèm: <ảnh/handoff, hoặc docs/design/<ten-man>/>.

PHẠM VI
- File được sửa: <FILE CHÍNH>, các widget trong <THƯ MỤC WIDGET>, và
  lib/core/ui/widgets nếu cần thêm/chỉnh component dùng chung.
- KHÔNG sửa: domain/, data/, presentation/controllers/, presentation/providers/,
  lib/app/router/, lib/core/auth/access_policy.dart, API, DTO. Nếu thiết kế buộc
  phải đổi các phần đó, dừng lại và hỏi tôi trước.

QUY TRÌNH
1. Đọc màn hiện tại, các widget nó dùng, controller (chỉ đọc), tài liệu nghiệp vụ
   <DOC> và test trong <THƯ MỤC TEST>.
2. Trước khi sửa, viết ra checklist hành vi hiện có: mọi nút/hành động, điều kiện
   hiện/ẩn/khóa theo quyền (AccessPolicy, permission, feature), dialog xác nhận,
   trạng thái loading/empty/error/partial/không quyền, điều hướng đi đâu, chữ/Key mà
   test đang tìm. Gộp thêm các điểm nghiệp vụ tôi liệt kê bên dưới.
3. So checklist với thiết kế, chỉ ra chỗ thiết kế bỏ sót hành vi hoặc mâu thuẫn
   nghiệp vụ. Hành vi đó giữ nguyên, không bỏ.
4. Sửa giao diện. Mỗi nút mới vẫn gọi đúng method controller cũ với cùng tham số,
   cùng điều kiện enable/disable, cùng xác nhận.
5. Chạy kiểm tra (mục KIỂM TRA), sửa đến khi xanh.
6. Báo cáo: checklist từng dòng (giữ / đổi cách trình bày / có vấn đề), file đã
   sửa, test đã chạy kèm kết quả, ảnh/golden đã cập nhật.

QUY TẮC GIAO DIỆN (docs/ui-design-system.md)
- Màu chỉ qua colorScheme và context.tone(AppTone.x); không mã màu thô, không
  Colors.* (trừ trắng/đen/trong suốt), không AppColors.grey* mới.
- Chữ qua Theme.of(context).textTheme (money, moneyLarge, caption); không
  fontSize cứng. Bo góc/khoảng cách qua AppRadius/AppSpacing.
- Dùng component chung (StatusBadge, SectionHeader, AppSectionCard, StatTile,
  MoneyText, EmptyState/ErrorState/ErrorBanner/ListSkeleton, AppSearchField,
  showAppConfirmDialog, ResponsiveColumns/ResponsiveSliverColumns, ElapsedText,
  AppNetworkImage). Không viết lại badge/tiêu đề/khung lỗi trong feature.
- Màn trong shell không tự tạo Scaffold/AppBar. Vùng chạm ≥ 48. Form rộng tối đa
  ~720. Phải vừa 320dp với cỡ chữ 200%.
- Hiệu năng: ref.watch(p.select(...)) ở widget lá; danh sách dài dùng sliver dựng
  lười; không Timer.periodic + setState cả màn; không Opacity/BoxShadow mờ trên
  từng phần tử danh sách; MediaQuery.sizeOf thay MediaQuery.of.
- Giữ Key và Semantics hiện có. Nếu buộc đổi chữ mà test đang tìm, cập nhật test
  và nêu rõ trong báo cáo; không xóa test, không nới assert để cho qua.

NGHIỆP VỤ PHẢI GIỮ CỦA MÀN NÀY
<DÁN MỤC "Nghiệp vụ phải giữ" CỦA MÀN>

KIỂM TRA
- dart format lib test, dart fix --apply, flutter analyze (không cảnh báo mới).
- flutter test <THƯ MỤC TEST>
- flutter test test/app test/architecture test/core
  (guard màu/style là ratchet: chỉ được giảm; khi giảm thì hạ trần trong
  test/app/theme/style_tokens_test.dart cùng commit).
- <GOLDEN NẾU CÓ>: chỉ --update-goldens khi đổi giao diện có chủ đích; mở ảnh mới
  ra xem và mô tả khác biệt trước khi chấp nhận.
- Kết thúc bằng flutter test (toàn bộ).
```

---

## 3. Phần riêng từng màn

Mỗi màn gồm: mục tiêu UX, nghiệp vụ phải giữ (dán vào khung ở mục 2), prompt
Claude Design, và thông tin file/test cho Claude Code.

### 3.1 Khung app: tab dưới, rail, sidebar

- **File**: `lib/app/shell/app_shell.dart`, `shell_tabs.dart`, `shell_sections.dart`,
  `lib/core/ui/sidebar/`, `lib/app/realtime_notice.dart`
- **Test**: `test/app`, `test/widget_test.dart`

**Mục tiêu UX**: biết ngay mình đang ở đâu; số việc chờ (yêu cầu QR, cảnh báo kho)
thấy được từ mọi màn; trạng thái kết nối realtime rõ nhưng không làm phiền.

**Nghiệp vụ phải giữ**
- Mục nào hiện do permission + feature quyết định (sidebar filter); danh sách tab
  theo vai trò chỉ là thứ tự ưu tiên, không cấp quyền. Mục đầu tiên người dùng mở
  được là màn khởi động.
- Màn đổi phạm vi truy cập (scope) phải remount (giữ `ValueKey(AccessPolicy.xScope)`).
- Action trên AppBar do từng section đóng góp (lọc Thực đơn, lọc Báo cáo).
- Thu ngân/super admin vẫn bị chặn sang web-only như hiện tại.

```text
Thiết kế lại khung điều hướng của Xây POS (theo Prompt nền).
Hiện tại: <ảnh chụp>.
Cần:
1. Điện thoại: thanh tab dưới (tối đa 4 mục theo vai trò + "Khác"). Badge số cho
   mục có việc chờ. "Khác" mở sidebar đầy đủ chia nhóm (Bán hàng, Báo cáo, Kho,
   Quản trị) — chỉ hiện mục người dùng có quyền.
2. Tablet ngang: rail 88px (icon + nhãn ngắn + badge), mục đang chọn nổi bật rõ;
   nút menu mở sidebar đầy đủ.
3. AppBar: tiêu đề màn, chỗ cho 1–2 action của màn (lọc), chỉ báo kết nối realtime
   dạng chấm nhỏ (đang kết nối / mất kết nối / đang kiểm tra định kỳ) chạm vào xem
   chi tiết.
4. Thông báo realtime (ví dụ "Có 2 yêu cầu QR mới") dạng banner ngắn không che nút.
Vẽ cho 4 vai trò: Chủ quán, Quản lý, Nhân viên phục vụ, Bếp.
```

### 3.2 Gọi món — sơ đồ bàn (`/app/order-create`)

- **File**: `lib/features/order/presentation/screens/order_service_context_screen.dart`,
  `lib/features/qr_order/presentation/widgets/`
- **Doc**: `docs/order-management.md`, `docs/qr-order-management.md`
- **Test**: `test/features/order`, `test/features/qr_order`
- **Golden**: `test/features/order/goldens/order_service_context.png`,
  `test/features/qr_order/goldens/qr_table_workspace.png`

**Mục tiêu UX**: giờ cao điểm nhìn một giây biết bàn nào trống, bàn nào chờ xác
nhận, bàn nào có yêu cầu QR; chạm một lần vào đúng việc.

**Nghiệp vụ phải giữ**
- Bộ lọc Tất cả / Sử dụng / Còn trống lọc trên dữ liệu đã tải đủ trang; không đổi
  TableStatus. Chip khu vực lấy từ khu vực thực tế (tải đủ trang). Tên không hardcode.
- Màu bàn: đơn chưa xác nhận (vàng), đã xác nhận (xanh), còn trống. Tổng tiền chỉ
  lấy từ serving order của phiên hiện tại; không bịa tổng tiền/số món, không gọi
  API riêng cho từng thẻ.
- Chạm bàn có bill mở thẳng chi tiết đơn; chạm bàn trống mở chọn món. Chọn bàn
  không mở phiên.
- Nhãn "QR · n yêu cầu mới" đếm số yêu cầu (không phải số món), chỉ tính yêu cầu
  của phiên hiện tại hoặc chưa gắn phiên; QR chưa duyệt không làm bàn bận, không
  cộng tiền. Chạm nhãn mở yêu cầu của bàn đó; nút "Yêu cầu QR (n)" mở toàn bộ.
- Duyệt QR: mở chi tiết để tải mới, ô xác nhận rồi "Duyệt yêu cầu"; từ chối bắt
  buộc lý do 1–1000 ký tự rồi "Xác nhận từ chối".
- Mang đi là ô hành động riêng, không có bàn/phiên.

```text
Thiết kế lại màn "Gọi món" (sơ đồ bàn) của Xây POS.
Hiện tại: <ảnh chụp>.
Nội dung: lưới thẻ bàn (2 cột điện thoại, nhiều cột tablet), bộ lọc Tất cả / Sử dụng
/ Còn trống kèm số lượng, chip khu vực cuộn ngang, ô "Mang đi" và nút "Yêu cầu QR (n)".
Mỗi thẻ bàn: tên bàn, khu vực, trạng thái (Trống / Chờ xác nhận / Đang phục vụ) bằng
màu + chữ, tổng tiền bill nếu có, thời gian phục vụ, nhãn "QR · n yêu cầu mới".
Mục tiêu: đọc trạng thái trong 1 giây, phân biệt được cả khi mù màu, bàn có việc
cần làm (chờ xác nhận, có QR) nổi hơn bàn bình thường.
Vẽ thêm: hàng đợi yêu cầu QR (bottom sheet điện thoại / panel phải tablet) và hộp
duyệt/từ chối (đối chiếu món, giá lúc gửi và giá hiện tại, ô xác nhận, lý do từ chối).
Trạng thái: đang tải, không có bàn, lỗi, dữ liệu cũ, 60 bàn trên tablet.
```

### 3.3 Chọn món / tạo đơn (`/app/order-create?tableId=…`, mang đi)

- **File**: `order_create_screen.dart`, widget `order_menu_picker.dart`,
  `order_menu_item_card.dart`, `menu_item_sheet.dart`, `order_cart_layout.dart`,
  `order_exit_guard.dart`, `stock_shortage_dialog.dart`, `takeaway_submitted_view.dart`
- **Doc**: `docs/order-management.md`, `docs/direct-stock-menu-items.md`
- **Test**: `test/features/order`

**Mục tiêu UX**: thêm món nhanh nhất có thể (tìm, lọc nhóm, chạm +), luôn thấy giỏ
và tổng tiền, gửi đơn một chạm, khó gửi nhầm.

**Nghiệp vụ phải giữ**
- "Gửi đơn" dùng tableId + SUBMIT, backend tạo phiên nếu cần và xác nhận đơn trong
  một request. "Tạo nháp" chỉ có ở phiên legacy/mang đi — không hiện thêm nơi khác.
- Nút gửi khóa khi đang gửi; timeout/lỗi mạng giữ nguyên ý định để thử lại đúng
  request (không tạo đơn thứ hai).
- Rời màn khi giỏ có món phải qua hộp xác nhận (exit guard).
- Thiếu kho hiện hộp thiếu kho; món hết/không bán theo dữ liệu menu.
- Số lượng có thể là số thập phân; không làm tròn.

```text
Thiết kế lại màn chọn món của Xây POS cho 2 trường hợp: tại bàn và mang đi.
Hiện tại: <ảnh chụp>.
- Điện thoại: ô tìm món dính trên đầu, chip nhóm món cuộn ngang, danh sách/lưới món
  (ảnh nhỏ, tên, giá, nút +, số lượng đã chọn hiện ngay trên thẻ). Thanh giỏ dính
  đáy: số món, tổng tiền, nút "Gửi đơn". Chạm thanh giỏ mở sheet giỏ: sửa số lượng,
  ghi chú từng món, xóa món.
- Tablet ngang: trái là menu, phải là giỏ luôn hiện (bàn/khách, danh sách món, tổng,
  "Gửi đơn"; mang đi có thêm "Tạo nháp").
- Sheet chi tiết món (tùy chọn, ghi chú, số lượng).
- Hộp thiếu nguyên liệu, hộp "Bỏ giỏ hàng?" khi thoát, trạng thái đang gửi, gửi lỗi
  có "Thử lại", màn "Đã gửi" cho mang đi.
Ưu tiên: thao tác một tay, ngón cái chạm được nút chính, hạn chế nhập phím.
```

### 3.4 Chi tiết đơn & thanh toán (`/app/order-create/bill/:orderId`, `/app/orders/:id`)

- **File**: `order_detail_screen.dart`, widget `order_payment_dialog.dart`,
  `transfer_qr_panel.dart`, `order_line_actions.dart`, `order_mutation_forms.dart`,
  `order_ingredient_dialog.dart`, `order_widgets.dart`;
  `lib/features/tables/presentation/widgets/table_transfer_dialog.dart`
- **Doc**: `docs/order-settlement.md`, `docs/transfer-account.md`,
  `docs/table-session-transfer.md`, `docs/order-ingredient-inspection.md`
- **Test**: `test/features/order`, `test/features/tables`

**Mục tiêu UX**: thu ngân thấy ngay phải thu bao nhiêu, thu xong hoàn tất trong
2–3 chạm; trạng thái từng món và đơn rõ ràng; thao tác nguy hiểm khó bấm nhầm.

**Nghiệp vụ phải giữ**
- Thanh cuối: Tạm tính + "Thanh toán hóa đơn". Backend báo PAID mới chuyển sang
  "Hoàn tất đơn". COMPLETED hiện "Đã hoàn tất"; CANCELLED không có thanh toán/hoàn tất.
- Hoàn tất khi còn món chưa SERVED: người có ORDER_MARK_SERVED xác nhận "đã phục vụ
  tất cả" rồi mới gửi (mark-served hàng loạt rồi complete).
- Thanh toán: chọn Tiền mặt hoặc Chuyển khoản một chạm. Tiền mặt: ô "Khách đưa" và
  nút gợi ý (Đủ tiền, mệnh giá tròn kế tiếp), chỉ để tính tiền thừa trên máy; nhỏ hơn
  số cần thu thì khóa nút và hiện "Còn thiếu". Chuyển khoản: bắt buộc mã tham chiếu;
  có tài khoản nhận thì hiện VietQR (nền trắng, chạm để phóng to), điền sẵn nội dung
  vào ô tham chiếu nếu đang trống; QR chỉ hiển thị, không tạo payment.
- Nút xác nhận ghi rõ "Đã nhận <số tiền>". Khi đang chờ kết quả/cần đối chiếu: ẩn
  phần tiền thừa, chỉ còn bước khôi phục (tải lại để xác minh), không tạo payment mới.
- Thao tác từng món theo quyền; chuyển bàn ở menu ba chấm (TABLE_TRANSFER), giữ
  nguyên route/orderId; "Xem nguyên liệu" theo quyền.
- FAB "+" gọi thêm món chỉ khi đơn OPEN/CONFIRMED.

```text
Thiết kế lại màn chi tiết đơn và hộp thanh toán của Xây POS.
Hiện tại: <ảnh chụp chi tiết đơn, hộp thanh toán tiền mặt, chuyển khoản có QR>.
Chi tiết đơn: đầu màn (mã đơn, bàn/mang đi, trạng thái đơn, thời gian, số khách),
danh sách món (tên, số lượng, đơn giá, thành tiền, trạng thái món: Chờ / Đang nấu /
Xong / Đã phục vụ / Đã hủy, ghi chú), menu thao tác từng món, thanh đáy dính: Tạm tính
+ nút chính theo trạng thái (Thanh toán hóa đơn → Hoàn tất đơn → Đã hoàn tất).
FAB "+" gọi thêm món. Menu ba chấm: Chuyển bàn, Xem đơn trong phiên.
Hộp thanh toán: số cần thu thật to; 2 nút lớn Tiền mặt / Chuyển khoản.
- Tiền mặt: ô Khách đưa (bàn phím số), chip gợi ý mệnh giá, dòng Tiền thừa hoặc
  "Còn thiếu" (đỏ, nút khóa).
- Chuyển khoản: QR VietQR + ngân hàng, số tài khoản, chủ tài khoản, nội dung; ô mã
  tham chiếu; trường hợp chưa cài tài khoản nhận.
- Nút xác nhận "Đã nhận 350.000 ₫". Trạng thái đang gửi, lỗi mạng cần xác minh
  (chỉ còn nút Tải lại để kiểm tra).
Hộp "Hoàn tất đơn" khi còn món chưa phục vụ. Tablet: chi tiết đơn trái, thanh toán
phải (không cần dialog).
```

### 3.5 Gọi thêm món (`/app/order-create/bill/:orderId/add-items`)

- **File**: `order_append_screen.dart`, `order_append_navigation.dart` (dùng chung
  picker/giỏ với 3.3)
- **Doc**: `docs/order-management.md`
- **Test**: `test/features/order`

**Nghiệp vụ phải giữ**
- Chỉ gọi thêm vào đơn đã chọn (OPEN/CONFIRMED); không tự tạo đơn mới, không đổi
  trạng thái bàn.
- Key/version bất biến cho mỗi lần gửi; timeout thì thử lại đúng request.
- Exit guard khi giỏ gọi thêm có món.

```text
Thiết kế màn "Gọi thêm món" dùng lại bố cục chọn món (màn trước) nhưng phân biệt rõ
đây là thêm vào đơn đang có: đầu màn ghi "Gọi thêm cho Bàn 5 · Đơn #A123", hiển thị
gọn các món đã gọi (thu gọn được), giỏ chỉ chứa món gọi thêm, nút "Gửi món thêm".
Trạng thái đang gửi, lỗi + Thử lại, đơn không còn nhận thêm món.
```

### 3.6 Đơn hàng và Đơn mang đi (`/app/orders`, `/app/takeaway`)

- **File**: `order_list_screen.dart`, `takeaway_orders_screen.dart`,
  `takeaway_order_card.dart`
- **Doc**: `docs/order-management.md`
- **Test**: `test/features/order`

**Nghiệp vụ phải giữ**
- Đơn hàng: tìm theo mã, lọc trạng thái/loại đơn, sắp xếp, phân trang; lọc theo
  phiên khi có `?tableSessionId=`; mở chi tiết giữ sidebar "Đơn hàng".
- Mang đi: danh sách đơn đang xử lý, "Tạo đơn mang đi" (cần MENU_VIEW), "Xem lịch
  sử", "Tải lại"; không có quyền ORDER_VIEW thì hiện thông báo không quyền.

```text
Thiết kế lại "Đơn hàng" và "Đơn mang đi" của Xây POS.
Đơn hàng: ô tìm mã đơn, chip lọc nhanh trạng thái, nút Bộ lọc mở sheet (loại đơn,
sắp xếp), danh sách thẻ đơn (mã, bàn/mang đi, giờ, số món, tổng tiền, trạng thái),
cuộn vô hạn. Tablet: danh sách trái + chi tiết phải.
Mang đi: dạng bảng theo cột trạng thái (Chờ / Đang làm / Sẵn sàng giao) trên tablet,
danh sách nhóm theo trạng thái trên điện thoại; nút "Tạo đơn mang đi" nổi bật.
Trạng thái: rỗng, đang tải, lỗi, không có quyền xem đơn, lọc không có kết quả.
```

### 3.7 Màn hình bếp — KDS (`/app/kitchen`)

- **File**: `kitchen_display_screen.dart`, `kitchen_cards.dart`,
  `kitchen_action_confirmation_dialog.dart`
- **Doc**: `docs/kitchen-display.md`
- **Test**: `test/features/kitchen`

**Mục tiêu UX**: đọc được từ 1–2 m; món chờ lâu nổi bật; chạm lớn, khó bấm nhầm khi
tay ướt/đeo găng.

**Nghiệp vụ phải giữ**
- Hai chế độ Theo món / Theo đơn, lọc trạng thái, tìm kiếm cục bộ (debounce 300ms,
  không tạo request).
- Nút theo quyền: "Bắt đầu nấu" (KITCHEN_START_COOKING), "Đã xong" và "Ready cả đơn"
  (KITCHEN_MARK_READY); giữ hộp xác nhận hiện có.
- Theo đơn hiển thị mọi dòng đã tải của đơn khớp lọc; tiến độ chỉ đếm dòng trong
  queue. Tổng hợp theo món giữ số lượng thập phân, không cộng khác đơn vị.
- Giờ chờ tính từ sentToKitchenAt (fallback createdAt), cảnh báo sau 20 phút.
- Làm mới một phần: giữ dữ liệu cũ, báo chưa đầy đủ và khóa thao tác hàng loạt;
  phiên bản lẫn lộn của cùng đơn được đánh dấu cần đối chiếu.
- Card cao theo nội dung, ghi chú hiện đầy đủ; giảm số cột khi chữ lớn; header,
  card và tổng hợp nằm cùng vùng cuộn. Poll 12 giây do controller lo — không đổi.

```text
Thiết kế lại màn hình bếp (KDS) của Xây POS cho tablet ngang đặt cách 1–2 m,
có cả bản điện thoại.
Chế độ Theo đơn: thẻ đơn (bàn hoặc mang đi, mã đơn, thời gian chờ to, danh sách món
với số lượng to + ghi chú đầy đủ + trạng thái từng món, nút "Ready cả đơn").
Chế độ Theo món: gom theo món (tổng số lượng + đơn vị, các bàn đang chờ món đó).
Thanh trên: chuyển chế độ, chip trạng thái Chờ / Đang nấu / Xong kèm số đếm, tìm kiếm.
Màu theo thời gian chờ (bình thường → quá 20 phút nổi bật đỏ/cam, có icon).
Nút "Bắt đầu nấu" / "Đã xong" cao ≥ 56dp. Hộp xác nhận.
Trạng thái: dữ liệu chưa đầy đủ (banner, khóa thao tác hàng loạt), cần đối chiếu,
mất kết nối, rỗng ("Bếp đang trống"), chữ hệ thống 200%.
```

### 3.8 Tổng quan (`/app/overview`)

- **File**: `lib/features/overview/presentation/screens/overview_screen.dart`,
  `lib/core/ui/widgets/stat_tile.dart`
- **Test**: `test/features/overview`

**Nghiệp vụ phải giữ**
- Các chỉ số: Doanh thu hôm nay, Tiền đã thu, Đơn hoàn tất, Đơn đã hủy, Giá trị
  TB/đơn, Bàn đang phục vụ, Đơn mang đi đang chờ, Yêu cầu QR chờ duyệt, Nguyên liệu
  sắp hết — mỗi khối chỉ hiện khi có quyền, lỗi riêng từng khối ("Chưa đồng bộ được"
  + Thử lại), không tự tính số khi API không trả.
- Lối tắt: mở sơ đồ gọi món, bảng đơn mang đi, danh sách tồn kho thấp.

```text
Thiết kế lại "Tổng quan" cho chủ quán/quản lý (điện thoại và tablet).
Phần trên: "Hôm nay" — Doanh thu, Tiền đã thu, Đơn hoàn tất, Đơn hủy, Giá trị TB/đơn
(thẻ KPI, số tiền lớn thẳng cột).
Phần "Đang diễn ra": Bàn đang phục vụ, Đơn mang đi đang chờ, Yêu cầu QR chờ duyệt,
Nguyên liệu sắp hết — mỗi thẻ có nút đi tới màn xử lý. Việc cần làm ngay đặt lên trên.
Trạng thái từng thẻ: đang tải, lỗi riêng (thẻ khác vẫn hiện), không có quyền (ẩn thẻ).
```

### 3.9 Báo cáo: Doanh thu ngày, Báo cáo, Giá vốn & lãi tham chiếu

- **File**: `lib/features/reports/presentation/`,
  `lib/features/reference_margin_reports/presentation/`
- **Doc**: `docs/revenue-reports.md`, `docs/reference-margin-reports.md`
- **Test**: `test/features/reports`, `test/features/reference_margin_reports`

**Nghiệp vụ phải giữ**
- Doanh thu ngày (REPORT_DAILY_VIEW + DAILY_REVENUE) và Báo cáo (REPORT_DETAIL_VIEW
  + DETAIL_REPORT) độc lập, không cấp quyền chéo.
- Báo cáo: khoảng ngày tối đa 366 ngày, 3 tab Tổng quan / Món bán chạy / Đơn đối
  chiếu; bộ lọc mở từ action trên AppBar.
- Ngày theo múi giờ nhà hàng; tiền giữ đúng độ chính xác backend trả, không làm
  tròn khác; meta (khoảng ngày, thời điểm tạo) vẫn hiển thị.
- Giá vốn & lãi tham chiếu: tab Tổng quan / Đơn đối chiếu, mức độ phủ dữ liệu
  (coverage) phải thấy rõ; không quyền thì hiện thông báo hiện có.

```text
Thiết kế lại 3 màn báo cáo của Xây POS: Doanh thu ngày, Báo cáo doanh thu (khoảng
ngày), Giá vốn & lãi tham chiếu.
- Chọn ngày/khoảng ngày nhanh (Hôm nay, Hôm qua, 7 ngày, Tháng này, Tùy chọn ≤ 366 ngày).
- Thẻ KPI, biểu đồ doanh thu theo ngày/giờ, cơ cấu phương thức thanh toán, top món,
  bảng đơn đối chiếu (điện thoại: danh sách thẻ; tablet: bảng).
- Giá vốn & lãi: nêu rõ đây là số "tham chiếu", hiện mức độ phủ (bao nhiêu % món có
  giá vốn) bằng màu + chữ.
- Trạng thái: không có dữ liệu trong khoảng ngày, đang tải, lỗi, không có quyền.
Biểu đồ đơn giản, đọc được trên 360dp, có số liệu khi chạm.
```

### 3.10 Sổ quỹ (`/app/cashbook`)

- **File**: `lib/features/cashbook/presentation/`
- **Test**: `test/features/cashbook`

**Nghiệp vụ phải giữ**
- Xem cần CASHBOOK_VIEW; "Ghi nhận khoản chi" chỉ khi có CASHBOOK_CREATE.
- Giữ thẻ tổng hợp, biểu đồ dòng tiền, bảng bút toán, bộ lọc, chi tiết khoản chi,
  chọn phiếu nhập kho khi ghi chi; validation form như hiện tại.

```text
Thiết kế lại "Sổ quỹ": thẻ tổng thu / tổng chi / chênh lệch theo khoảng ngày, biểu
đồ dòng tiền, danh sách bút toán (điện thoại: thẻ nhóm theo ngày; tablet: bảng),
bộ lọc dạng sheet, nút "Ghi nhận khoản chi" nổi bật, form khoản chi (số tiền bàn phím
số, danh mục, ghi chú, gắn phiếu nhập kho), hộp chi tiết khoản chi.
Trạng thái rỗng, lỗi, không có quyền ghi chi (ẩn nút).
```

### 3.11 Thực đơn và công thức (`/app/menu`, `/app/menu/items/:id/recipes`)

- **File**: `lib/features/menu/presentation/`
- **Doc**: `docs/menu-management.md`, `docs/recipe-management.md`,
  `docs/recipe-application-and-cost-config.md`, `docs/direct-stock-menu-items.md`,
  `docs/ingredients-management.md`
- **Test**: `test/features/menu`

**Nghiệp vụ phải giữ**
- 3 tab Món bán / Nhóm món / Nguyên liệu, mỗi tab chỉ hiện khi có quyền; tìm, lọc
  (action trên AppBar), sắp xếp, phân trang.
- Chế độ kho của món (Không theo dõi / Trừ kho trực tiếp / Theo công thức) với điều
  kiện bật theo feature hiện có (`AccessPolicy.canSetInventoryMode`); áp dụng công
  thức theo `canSetRecipeApplication`.
- Validation giá, tên, URL ảnh, thứ tự; sửa chỉ gửi trường đổi; xóa/ẩn có xác nhận.

```text
Thiết kế lại "Thực đơn" và "Công thức món".
Thực đơn: 3 tab (Món bán, Nhóm món, Nguyên liệu). Món bán: lưới thẻ món (ảnh, tên,
giá, nhóm, trạng thái bán/ngừng, nhãn chế độ kho), tìm kiếm, chip nhóm, FAB thêm.
Form món: ảnh, tên, giá, nhóm, chế độ kho (3 lựa chọn có giải thích ngắn, lựa chọn
không khả dụng thì mờ + lý do), bật/tắt bán.
Công thức: danh sách nguyên liệu + định lượng + đơn vị, bảng giá vốn ước tính, nút
thêm nguyên liệu (tìm kiếm).
Tablet: danh sách trái + chi tiết/form phải.
```

### 3.12 Bàn và khu vực (`/app/tables`)

- **File**: `lib/features/tables/presentation/`
- **Doc**: `docs/table-management.md`, `docs/table-session-transfer.md`
- **Test**: `test/features/tables`

**Nghiệp vụ phải giữ**
- Khu vực và bàn: tìm, lọc, sắp xếp, phân trang, tạo/sửa/bật-tắt/xóa mềm; bàn gán
  khu vực và quản lý QR.
- Phiên: mở, xem, sửa số khách/ghi chú, chuyển bàn (TABLE_TRANSFER, giữ idempotency
  và "thử lại đúng request"), hủy mở nhầm, lịch sử phiên và lịch sử chuyển bàn.
- Thông báo chuyển bàn không khẳng định "đã chuyển đến B" khi kết quả là bàn khác.

```text
Thiết kế lại "Quản lý bàn": tab Bàn / Khu vực; lưới thẻ bàn (tên, sức chứa, khu vực,
trạng thái hoạt động, phiên đang mở). Chi tiết bàn: thông tin, QR bàn (xem/tải/in),
phiên hiện tại (số khách, ghi chú, giờ mở) với Chuyển bàn, Hủy mở nhầm, Lịch sử.
Hộp chuyển bàn: chọn bàn đích (lọc theo khu vực, bàn đang bận bị khóa), lý do tùy chọn.
Form bàn/khu vực, xác nhận xóa. Trạng thái rỗng, lỗi, đang gửi, xung đột (bàn vừa
có khách).
```

### 3.13 Nhân viên (`/app/staff`)

- **File**: `lib/features/staff/presentation/`
- **Doc**: `docs/staff-management-handover.md`
- **Test**: `test/features/staff`

**Nghiệp vụ phải giữ**
- Danh sách thẻ, tìm debounce 350ms, lọc vai trò/trạng thái, 4 kiểu sắp xếp, phân trang.
- Hiện giới hạn số nhân viên `maxStaff` (null = không giới hạn) từ gói.
- Chủ quán, super admin, vai trò tùy chỉnh và chính mình được bảo vệ (không có thao
  tác không hợp lệ). Ngừng hoạt động bắt buộc lý do ≤ 500 ký tự.
- Đổi vai trò cảnh báo xóa quyền riêng; đổi email/vai trò thu hồi phiên đăng nhập.
- Phân quyền cần STAFF_MANAGEMENT + STAFF_PERMISSION; khóa lưu khi danh mục quyền
  lỗi/chưa tải.

```text
Thiết kế lại "Nhân viên": đầu màn hiện "12 / 20 nhân viên" theo gói; tìm kiếm, chip
vai trò/trạng thái, thẻ nhân viên (tên, vai trò, liên hệ, trạng thái). Chi tiết với
Sửa, Ngừng hoạt động/Kích hoạt (lý do bắt buộc), Phân quyền.
Màn phân quyền: nhóm quyền theo chức năng, mỗi quyền có 3 trạng thái (theo vai trò /
cấp thêm / chặn) và hiện quyền hiệu lực.
Tài khoản được bảo vệ: không có nút thao tác + giải thích ngắn.
```

### 3.14 Kho: Tồn kho, Chứng từ, Cảnh báo, Kiểm kê

- **File**: `lib/features/inventory/presentation/` (dùng chung
  `inventory_section_screen.dart`)
- **Doc**: `docs/inventory-navigation.md`, `docs/inventory-phase-*.md`,
  `docs/inventory-alert-realtime.md`
- **Test**: `test/features/inventory`

**Nghiệp vụ phải giữ**
- 4 mục sidebar (Tồn kho, Chứng từ kho, Cảnh báo tồn kho, Kiểm kê); Biến động kho và
  Quản lý kho mở từ Tồn kho như màn con có nút quay lại về Tồn kho.
- Bộ lọc "Chỉ tồn thấp" chỉ hiện khi có quyền xem cảnh báo; chọn kho dùng selector cũ.
- Mỗi thao tác theo permission + feature riêng (nhập, xuất, điều chỉnh, ngưỡng,
  xác nhận cảnh báo, quản lý/xác nhận kiểm kê).
- Kiểm kê: thoát khi đang đếm phải qua exit guard; xác nhận phiếu kiểm kê là thao
  tác có xác nhận.

```text
Thiết kế lại phân hệ Kho:
- Tồn kho: chọn kho, tìm nguyên liệu, chip "Chỉ tồn thấp", danh sách (tên, tồn hiện
  tại + đơn vị, ngưỡng, thanh mức tồn, nhãn Thấp/Hết); nút Biến động kho, Quản lý kho.
- Chứng từ kho: danh sách phiếu nhập/xuất/điều chỉnh, tạo phiếu (chọn nguyên liệu,
  số lượng, đơn giá), chi tiết phiếu.
- Cảnh báo: danh sách cảnh báo mới/đã xem, nút Xác nhận đã xem.
- Kiểm kê: danh sách đợt, màn đếm (nhập số thực tế từng nguyên liệu bằng bàn phím
  số, hiện chênh lệch), xác nhận đợt.
Ưu tiên nhập liệu nhanh trên điện thoại khi đứng trong kho.
```

### 3.15 Cài đặt (`/app/settings`)

- **File**: `lib/features/settings/presentation/`
- **Doc**: `docs/transfer-account.md`, `docs/menu-link-qr.md`
- **Test**: `test/features/settings`

**Nghiệp vụ phải giữ**
- Thông tin nhà hàng: xem theo RESTAURANT_PROFILE_VIEW, sửa theo
  RESTAURANT_PROFILE_UPDATE.
- Gói dịch vụ (SUBSCRIPTION_VIEW): trạng thái, ngày bắt đầu/hết hạn, còn lại, số
  nhân viên tối đa ("Không giới hạn" khi null), tính năng của gói.
- QR menu mang đi; Tài khoản nhận chuyển khoản: thêm/sửa/gỡ theo quyền, gỡ luôn hỏi
  xác nhận; tên chủ tài khoản hiện "Sẽ lưu là: …" khi bản chuẩn hóa khác; lỗi theo
  trường từ server hiện dưới ô.
- Công tắc "Cập nhật tự động" (realtime), phiên bản, chính sách quyền riêng tư,
  đăng xuất.

```text
Thiết kế lại "Cài đặt" dạng danh sách nhóm: Nhà hàng (tên, mã, múi giờ, tiền tệ,
liên hệ — nút Sửa nếu có quyền), Gói dịch vụ (thẻ trạng thái + ngày hết hạn + còn
lại, giới hạn nhân viên, tính năng), Bán hàng (QR menu mang đi, Tài khoản nhận chuyển
khoản), Ứng dụng (Cập nhật tự động, phiên bản, chính sách), Tài khoản (đăng xuất).
Hộp tài khoản chuyển khoản: chọn ngân hàng có tìm kiếm không dấu, số tài khoản, tên
chủ tài khoản với dòng "Sẽ lưu là: NGUYEN VAN A". Hộp xác nhận gỡ tài khoản.
```

### 3.16 Đăng nhập và các màn chặn

- **File**: `lib/features/auth/presentation/`, `lib/features/access/`,
  `lib/features/subscription/`, `lib/app/startup_configuration_error_app.dart`
- **Test**: `test/features/auth`, `test/features/access`

**Nghiệp vụ phải giữ**
- Đăng nhập: Gmail, Mật khẩu (Hiện/Ẩn), "Đăng ký nhà hàng" mở REGISTER_URL; chân
  trang hỗ trợ (SUPPORT_WEB_URL ẩn khi trống, SUPPORT_PHONE).
- Màn chặn: cần gói, gói không khả dụng, tính năng không khả dụng, không có chức
  năng nào, chỉ dùng web (thu ngân/admin), vai trò không hỗ trợ, lỗi phiên. Nút mua/
  gia hạn (SUBSCRIBE_URL) chỉ cho chủ quán và không hiện trên iOS.

```text
Thiết kế lại màn Đăng nhập (điện thoại dọc và tablet ngang) và bộ màn thông báo chặn
dùng chung một mẫu: minh họa đơn giản, tiêu đề, giải thích ngắn bằng ngôn ngữ người
dùng (không mã lỗi), một nút chính (Thử lại / Đăng xuất / Mở trang gia hạn) và liên
hệ hỗ trợ. Màn khởi động/khôi phục phiên: logo + tiến trình, không nháy.
```

---

## 4. Checklist nghiệm thu mỗi màn

- [ ] Checklist hành vi trong báo cáo của Claude Code: mọi dòng là "giữ" hoặc "đổi
      cách trình bày", không có dòng bị bỏ.
- [ ] Đăng nhập lần lượt bằng chủ quán, quản lý, nhân viên, bếp: nút/mục hiện đúng
      quyền, không hiện thừa.
- [ ] Bấm nhanh hai lần nút gửi/thanh toán/chuyển bàn: chỉ một request.
- [ ] Tắt mạng giữa chừng: màn báo lỗi, thử lại đúng thao tác, không mất giỏ/form.
- [ ] Điện thoại 360dp, màn 320dp chữ 200%, tablet ngang: không tràn, không cắt số tiền.
- [ ] `flutter analyze` sạch; `flutter test` xanh toàn bộ; guard màu/style không tăng.
- [ ] Golden (nếu có) đã xem ảnh trước khi cập nhật.
- [ ] Ảnh trước/sau lưu vào `docs/design/<ten-man>/`, commit riêng cho màn đó.
