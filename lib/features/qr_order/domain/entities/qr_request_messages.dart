String? qrRequestMessage(String? code) => switch (code) {
  'QR_ORDER_DRAFT_NOT_SUBMITTED' =>
    'Đơn tại bàn chưa xác nhận. Hãy xác nhận đơn bằng luồng nhân viên rồi tải lại yêu cầu QR.',
  'QR_ORDER_REQUEST_EXPIRED' => 'Yêu cầu QR đã hết hạn.',
  'QR_REQUEST_SESSION_CHANGED' =>
    'Phiên bàn đã thay đổi. Không gắn yêu cầu cũ vào lượt khách mới.',
  'QR_ORDER_CHECKOUT_IN_PROGRESS' ||
  'CHECKOUT_STARTED' => 'Bàn đang thanh toán; không nhận thêm món.',
  'QR_ORDER_UNAVAILABLE' =>
    'QR của bàn hoặc quyền lợi gọi món hiện không còn hợp lệ.',
  'QR_REVIEW_CONTEXT_CHANGED' =>
    'Giá hoặc ngữ cảnh bàn đã thay đổi. Hãy tải lại và xác nhận lại.',
  'CONCURRENT_QR_REQUEST_UPDATE' =>
    'Yêu cầu QR đã được cập nhật. Hãy tải lại để kiểm tra.',
  'QR_ORDER_REQUEST_NOT_FOUND' =>
    'Không tìm thấy yêu cầu QR hoặc bạn không có quyền xem.',
  'INVALID_QR_REQUEST_TRANSITION' =>
    'Yêu cầu QR đã được xử lý hoặc không còn ở trạng thái chờ duyệt. Hãy tải lại để kiểm tra.',
  'FORBIDDEN' => 'Bạn chưa có đủ quyền để duyệt yêu cầu này.',
  _ => null,
};
