import 'dart:async';

import 'package:flutter/material.dart';

/// The search box of list screens: search icon, clear button, optional
/// debounce so typing does not reload on every key.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    this.controller,
    this.hintText = 'Tìm kiếm',
    this.onChanged,
    this.onSubmitted,
    this.debounce = Duration.zero,
    this.autofocus = false,
    this.dense = true,
    this.fieldKey,
  });

  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Delay before [onChanged] fires; zero reports every key at once.
  final Duration debounce;
  final bool autofocus, dense;

  /// Key of the inner [TextField], for tests that type into it.
  final Key? fieldKey;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  TextEditingController? _own;
  Timer? _timer;

  TextEditingController get _controller =>
      widget.controller ?? (_own ??= TextEditingController());

  @override
  void dispose() {
    _timer?.cancel();
    _own?.dispose();
    super.dispose();
  }

  void _changed(String value) {
    final onChanged = widget.onChanged;
    if (onChanged == null) return;
    _timer?.cancel();
    if (widget.debounce == Duration.zero) {
      onChanged(value);
    } else {
      _timer = Timer(widget.debounce, () => onChanged(value));
    }
  }

  void _clear() {
    _controller.clear();
    _timer?.cancel();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: widget.fieldKey,
    controller: _controller,
    autofocus: widget.autofocus,
    textInputAction: TextInputAction.search,
    onChanged: _changed,
    onSubmitted: widget.onSubmitted,
    decoration: InputDecoration(
      isDense: widget.dense,
      hintText: widget.hintText,
      prefixIcon: const Icon(Icons.search),
      suffixIcon: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => _controller.text.isEmpty
            ? const SizedBox.shrink()
            : IconButton(
                tooltip: 'Xoá tìm kiếm',
                onPressed: _clear,
                icon: const Icon(Icons.close),
              ),
      ),
    ),
  );
}
