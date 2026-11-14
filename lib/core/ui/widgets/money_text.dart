import 'package:flutter/material.dart';

import '../../../app/theme/app_typography.dart';
import '../../formatters/money_format.dart';

enum MoneyTextSize { small, regular, large }

/// An amount in the app's money format, with tabular digits so amounts in a
/// column line up. [amount] is the API decimal string, e.g. "125000.00".
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.currency,
    this.size = MoneyTextSize.regular,
    this.color,
    this.textAlign,
  });

  final String amount;
  final String? currency;
  final MoneyTextSize size;
  final Color? color;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = switch (size) {
      MoneyTextSize.small => text.money.copyWith(
        fontSize: text.bodySmall?.fontSize,
      ),
      MoneyTextSize.regular => text.money,
      MoneyTextSize.large => text.moneyLarge,
    };
    return Text(
      formatMoney(amount, currency: currency),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: color == null ? style : style.copyWith(color: color),
    );
  }
}
