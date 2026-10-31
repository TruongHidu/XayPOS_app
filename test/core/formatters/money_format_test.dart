import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/formatters/money_format.dart';

void main() {
  test('money groups thousands and pads a lone decimal digit', () {
    expect(formatMoney('1250000'), '1.250.000');
    expect(formatMoney('1250000.00'), '1.250.000');
    expect(formatMoney('12.5'), '12,50');
    expect(formatMoney('250.25', currency: 'đ'), '250,25 đ');
    expect(formatMoney('250.2513'), '250,2513');
    expect(formatMoney('999'), '999');
  });

  test('an empty currency adds nothing', () {
    expect(formatMoney('1000', currency: ''), '1.000');
  });

  test('negative amounts keep their sign', () {
    expect(formatMoney('-1250000.5'), '-1.250.000,50');
    expect(formatMinorUnits(BigInt.from(-150)), '-1,50');
  });

  test('hundredths format like the matching decimal', () {
    expect(formatMinorUnits(BigInt.from(125000000)), '1.250.000');
    expect(formatMinorUnits(BigInt.from(1250), currency: 'VND'), '12,50 VND');
    expect(formatMinorUnits(BigInt.from(5)), '0,05');
  });

  test('quantities are not padded', () {
    expect(formatDecimal('0.500'), '0,5');
    expect(formatDecimal('1000'), '1.000');
  });
}
