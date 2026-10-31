import 'package:flutter/foundation.dart';
import '../../../reports/domain/entities/report_date.dart';
import '../../domain/entities/cashbook_filters.dart';
import '../../domain/entities/cashbook_meta.dart';
import '../widgets/cashbook_format.dart';

/// The date range and currency every tab reads. Edits stay in a draft until
/// applied, so an open filter panel never shifts the figures underneath it.
class CashbookRangeController extends ChangeNotifier {
  CashbookRangeController({ReportDate Function()? today}) {
    // Presets follow the restaurant's calendar once a response names its zone.
    _today = today ?? () => cashbookToday(_meta?.timezone);
    _applied = CashbookRangeFilter.initial(_today());
    _draft = _applied;
  }

  late final ReportDate Function() _today;
  late CashbookRangeFilter _applied, _draft;
  CashbookMeta? _meta;
  String? validationError;

  CashbookRangeFilter get applied => _applied;
  CashbookRangeFilter get draft => _draft;
  ReportDate get today => _today();

  /// Attribution of the latest response: timezone and resolved currency.
  CashbookMeta? get meta => _meta;
  bool get isFiltered => _applied != CashbookRangeFilter.initial(_today());

  void setDraftRange(ReportDateRange range) {
    _draft = _draft.copyWith(range: range);
    validationError = null;
    notifyListeners();
  }

  void setDraftCurrency(String? value) {
    final code = value?.trim().toUpperCase();
    _draft = _draft.copyWith(
      currencyCode: () => code == null || code.isEmpty ? null : code,
    );
    validationError = null;
    notifyListeners();
  }

  /// Returns false and keeps the draft when it is not a valid query.
  bool apply() {
    validationError = _draft.validate();
    if (validationError != null) {
      notifyListeners();
      return false;
    }
    _applied = _draft;
    notifyListeners();
    return true;
  }

  void reset() {
    _applied = CashbookRangeFilter.initial(_today());
    _draft = _applied;
    validationError = null;
    notifyListeners();
  }

  void discardDraft() {
    if (_draft == _applied && validationError == null) return;
    _draft = _applied;
    validationError = null;
    notifyListeners();
  }

  void reportMeta(CashbookMeta meta) {
    final previous = _meta;
    _meta = meta;
    if (previous?.timezone != meta.timezone ||
        previous?.currencyCode != meta.currencyCode ||
        previous?.fromDate != meta.fromDate ||
        previous?.toDate != meta.toDate) {
      notifyListeners();
    }
  }
}
