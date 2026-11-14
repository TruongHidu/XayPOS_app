import '../../../../core/errors/stock_shortage.dart';
import '../../../../core/values/ingredient_quantity.dart';

/// A cart line as the shortage summary sees it; used only to recover notes,
/// since the refused request never got saved and its line ids mean nothing.
class ShortageCartLine {
  const ShortageCartLine({
    required this.menuItemId,
    required this.quantity,
    this.note,
  });
  final String menuItemId;
  final IngredientQuantity quantity;
  final String? note;
}

enum ShortageVerdict {
  /// No portion can be made from stock: drop the dish.
  soldOut,

  /// [ShortageDish.reduceBy] fewer portions fit, other dishes unchanged.
  reduce,

  /// Every line is blocked by the others, so no safe number can be given.
  unknown,
}

/// One refused line of a dish. [note] is null when the cart line was found
/// without a note; [matched] is false when no cart line could be found.
class ShortagePortion {
  const ShortagePortion({
    required this.quantity,
    this.note,
    this.matched = false,
  });
  final IngredientQuantity quantity;
  final String? note;
  final bool matched;
}

/// Every refused line of one dish, folded into what staff need to do.
class ShortageDish {
  const ShortageDish({
    required this.menuItemId,
    required this.name,
    required this.unit,
    required this.portions,
    required this.requested,
    required this.verdict,
    this.canMake,
    this.reduceBy,
    this.sharedWith = const [],
    this.mayShareWithOthers = false,
    this.ingredients,
  });
  final String menuItemId, name, unit;
  final List<ShortagePortion> portions;
  final IngredientQuantity requested;
  final ShortageVerdict verdict;

  /// Set for [ShortageVerdict.reduce] only.
  final IngredientQuantity? canMake, reduceBy;

  /// Other refused dishes drawing on the same short ingredient. Known only
  /// when ingredient details were sent.
  final List<String> sharedWith;

  /// Without ingredient details: another dish might be using the same stock.
  final bool mayShareWithOthers;

  /// Short ingredients, once each; null for staff without inventory access.
  final List<StockShortIngredient>? ingredients;
}

/// Groups the refused lines by dish, in the order they were sent.
///
/// The server's per-line maximum holds every other line still, so for one
/// dish the capacity is that maximum plus the dish's other lines. Lines whose
/// maximum is zero are skipped: the others alone already exceed the stock, so
/// they say nothing about how much fits.
List<ShortageDish> summarizeShortage(
  StockShortage shortage, {
  List<ShortageCartLine> cart = const [],
}) {
  final portions = _matchPortions(shortage.lines, cart);
  final byDish = <String, List<int>>{};
  for (var i = 0; i < shortage.lines.length; i++) {
    byDish.putIfAbsent(shortage.lines[i].menuItemId, () => []).add(i);
  }
  final shortIds = {
    for (final entry in byDish.entries)
      entry.key: {
        for (final i in entry.value)
          ...?shortage.lines[i].shortIngredients?.map((r) => r.ingredientId),
      },
  };
  final detailed = shortage.lines.every((l) => l.shortIngredients != null);

  return [
    for (final entry in byDish.entries)
      _dish(
        [for (final i in entry.value) shortage.lines[i]],
        [for (final i in entry.value) portions[i]],
        sharedWith: detailed
            ? [
                for (final other in byDish.entries)
                  if (other.key != entry.key &&
                      shortIds[other.key]!.any(shortIds[entry.key]!.contains))
                    shortage.lines[other.value.first].itemName,
              ]
            : const [],
        mayShare:
            !detailed &&
            (entry.value.length == 1
                ? shortage
                      .lines[entry.value.single]
                      .sharesIngredientWithOtherLines
                : byDish.entries.any(
                    (other) =>
                        other.key != entry.key &&
                        other.value.any(
                          (i) =>
                              shortage.lines[i].sharesIngredientWithOtherLines,
                        ),
                  )),
      ),
  ];
}

ShortageDish _dish(
  List<StockShortageLine> lines,
  List<ShortagePortion> portions, {
  required List<String> sharedWith,
  required bool mayShare,
}) {
  final requested = lines.fold(
    BigInt.zero,
    (sum, l) => sum + l.requestedQuantity.scaled,
  );
  final ingredients = lines.any((l) => l.shortIngredients != null)
      ? _distinct([for (final l in lines) ...?l.shortIngredients])
      : null;

  BigInt? reduceBy;
  for (final line in lines) {
    final max = line.maxAvailableQuantity.scaled;
    if (max == BigInt.zero) continue;
    final cut = line.requestedQuantity.scaled - max;
    // The largest cut is the safe one: maxima are rounded down per line.
    if (reduceBy == null || cut > reduceBy) reduceBy = cut;
  }
  // Alone in the order and still no portion fits, or an ingredient is gone.
  final emptyStock =
      (lines.length == 1 && !lines.single.sharesIngredientWithOtherLines) ||
      (ingredients?.any((r) => r.availableQuantity.scaled == BigInt.zero) ??
          false);
  final verdict = reduceBy != null && reduceBy > BigInt.zero
      ? ShortageVerdict.reduce
      : lines.every((l) => l.soldOut) && emptyStock
      ? ShortageVerdict.soldOut
      : ShortageVerdict.unknown;
  final first = lines.first;
  return ShortageDish(
    menuItemId: first.menuItemId,
    name: first.itemName,
    unit: first.unit,
    portions: portions,
    requested: IngredientQuantity.fromScaled(requested),
    verdict: verdict,
    canMake: verdict == ShortageVerdict.reduce
        ? IngredientQuantity.fromScaled(requested - reduceBy!)
        : null,
    reduceBy: verdict == ShortageVerdict.reduce
        ? IngredientQuantity.fromScaled(reduceBy!)
        : null,
    sharedWith: sharedWith,
    mayShareWithOthers: mayShare,
    ingredients: ingredients,
  );
}

/// Lines come back in request order and only short ones are listed, so each
/// one is found by walking the cart forward: same dish, same quantity.
List<ShortagePortion> _matchPortions(
  List<StockShortageLine> lines,
  List<ShortageCartLine> cart,
) {
  var from = 0;
  return [
    for (final line in lines)
      () {
        for (var k = from; k < cart.length; k++) {
          final c = cart[k];
          if (c.menuItemId == line.menuItemId &&
              c.quantity.scaled == line.requestedQuantity.scaled) {
            from = k + 1;
            return ShortagePortion(
              quantity: line.requestedQuantity,
              note: c.note,
              matched: true,
            );
          }
        }
        return ShortagePortion(quantity: line.requestedQuantity);
      }(),
  ];
}

List<StockShortIngredient> _distinct(List<StockShortIngredient> rows) {
  final seen = <String>{};
  return [
    for (final row in rows)
      if (seen.add(row.ingredientId)) row,
  ];
}
