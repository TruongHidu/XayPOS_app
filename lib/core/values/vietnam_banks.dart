/// A bank in the NAPAS 247 network, identified by its 6-digit BIN (the
/// acquirer id VietQR puts in the code).
class VietnamBank {
  const VietnamBank(this.bin, this.shortName, this.name);

  final String bin;

  /// What customers know the bank by (`Vietcombank`).
  final String shortName;

  /// Full Vietnamese name, for search and the picker subtitle.
  final String name;
}

/// Common NAPAS banks, most used first. Not exhaustive: the server accepts
/// any 6-digit BIN, so an unknown one is shown by its number.
const vietnamBanks = <VietnamBank>[
  VietnamBank('970436', 'Vietcombank', 'Ngân hàng TMCP Ngoại thương Việt Nam'),
  VietnamBank('970415', 'VietinBank', 'Ngân hàng TMCP Công thương Việt Nam'),
  VietnamBank('970418', 'BIDV', 'Ngân hàng TMCP Đầu tư và Phát triển Việt Nam'),
  VietnamBank(
    '970405',
    'Agribank',
    'Ngân hàng Nông nghiệp và Phát triển Nông thôn Việt Nam',
  ),
  VietnamBank('970407', 'Techcombank', 'Ngân hàng TMCP Kỹ thương Việt Nam'),
  VietnamBank('970422', 'MB', 'Ngân hàng TMCP Quân đội'),
  VietnamBank('970416', 'ACB', 'Ngân hàng TMCP Á Châu'),
  VietnamBank('970432', 'VPBank', 'Ngân hàng TMCP Việt Nam Thịnh Vượng'),
  VietnamBank('970423', 'TPBank', 'Ngân hàng TMCP Tiên Phong'),
  VietnamBank('970403', 'Sacombank', 'Ngân hàng TMCP Sài Gòn Thương Tín'),
  VietnamBank('970441', 'VIB', 'Ngân hàng TMCP Quốc tế Việt Nam'),
  VietnamBank('970443', 'SHB', 'Ngân hàng TMCP Sài Gòn - Hà Nội'),
  VietnamBank(
    '970437',
    'HDBank',
    'Ngân hàng TMCP Phát triển Thành phố Hồ Chí Minh',
  ),
  VietnamBank('970448', 'OCB', 'Ngân hàng TMCP Phương Đông'),
  VietnamBank('970426', 'MSB', 'Ngân hàng TMCP Hàng Hải Việt Nam'),
  VietnamBank('970440', 'SeABank', 'Ngân hàng TMCP Đông Nam Á'),
  VietnamBank('970431', 'Eximbank', 'Ngân hàng TMCP Xuất Nhập khẩu Việt Nam'),
  VietnamBank('970449', 'LPBank', 'Ngân hàng TMCP Lộc Phát Việt Nam'),
  VietnamBank('970428', 'Nam A Bank', 'Ngân hàng TMCP Nam Á'),
  VietnamBank('970409', 'Bac A Bank', 'Ngân hàng TMCP Bắc Á'),
  VietnamBank('970425', 'ABBANK', 'Ngân hàng TMCP An Bình'),
  VietnamBank('970454', 'BVBank', 'Ngân hàng TMCP Bản Việt'),
  VietnamBank('970452', 'KienlongBank', 'Ngân hàng TMCP Kiên Long'),
  VietnamBank('970412', 'PVcomBank', 'Ngân hàng TMCP Đại Chúng Việt Nam'),
  VietnamBank('970419', 'NCB', 'Ngân hàng TMCP Quốc Dân'),
  VietnamBank('970427', 'VietABank', 'Ngân hàng TMCP Việt Á'),
  VietnamBank('970433', 'Vietbank', 'Ngân hàng TMCP Việt Nam Thương Tín'),
  VietnamBank('970438', 'BAOVIET Bank', 'Ngân hàng TMCP Bảo Việt'),
  VietnamBank('970430', 'PGBank', 'Ngân hàng TMCP Thịnh vượng và Phát triển'),
  VietnamBank('970400', 'Saigonbank', 'Ngân hàng TMCP Sài Gòn Công Thương'),
  VietnamBank('970429', 'SCB', 'Ngân hàng TMCP Sài Gòn'),
  VietnamBank('970424', 'Shinhan Bank', 'Ngân hàng TNHH MTV Shinhan Việt Nam'),
  VietnamBank('970457', 'Woori Bank', 'Ngân hàng TNHH MTV Woori Việt Nam'),
  VietnamBank('970458', 'UOB', 'Ngân hàng United Overseas Bank Việt Nam'),
  VietnamBank('546034', 'Cake', 'Ngân hàng số Cake by VPBank'),
  VietnamBank('546035', 'Ubank', 'Ngân hàng số Ubank by VPBank'),
];

final _byBin = {for (final bank in vietnamBanks) bank.bin: bank};

/// The listed bank with [bin], or null when it is not in [vietnamBanks].
VietnamBank? bankByBin(String? bin) => bin == null ? null : _byBin[bin.trim()];

/// Short bank name for display; an unlisted BIN shows as `BIN 970999`.
String bankLabel(String bin) => bankByBin(bin)?.shortName ?? 'BIN $bin';
