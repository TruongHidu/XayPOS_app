import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/values/vietnam_banks.dart';
import 'package:pos_saas_app/core/values/vietnamese_text.dart';

void main() {
  test('bankByBin finds listed banks and ignores unknown ones', () {
    expect(bankByBin('970436')?.shortName, 'Vietcombank');
    expect(bankByBin(' 970422 ')?.shortName, 'MB');
    expect(bankByBin('970405')?.shortName, 'Agribank');
    expect(bankByBin('970449')?.shortName, 'LPBank');
    expect(bankByBin('999999'), isNull);
    expect(bankByBin(null), isNull);
    expect(bankLabel('970407'), 'Techcombank');
    expect(bankLabel('999999'), 'BIN 999999');
  });

  test('every listed bank has a unique 6-digit BIN and names', () {
    final bins = vietnamBanks.map((bank) => bank.bin).toList();
    expect(bins.toSet().length, bins.length);
    for (final bank in vietnamBanks) {
      expect(bank.bin, matches(RegExp(r'^\d{6}$')));
      expect(bank.shortName.trim(), isNotEmpty);
      expect(bank.name.trim(), isNotEmpty);
    }
  });

  test('removeVietnameseDiacritics keeps case and other characters', () {
    expect(removeVietnameseDiacritics('Nguyễn Văn Đức'), 'Nguyen Van Duc');
    expect(removeVietnameseDiacritics('ĐẶNG THỊ ÁNH'), 'DANG THI ANH');
    expect(removeVietnameseDiacritics('Phở 24/7'), 'Pho 24/7');
    // NFD input: base letter + combining marks.
    expect(removeVietnameseDiacritics('Lề'), 'Le');
  });
}
