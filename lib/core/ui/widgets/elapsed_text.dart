import 'package:flutter/material.dart';

import '../controllers/minute_clock.dart';
import '../formatters/elapsed.dart';

/// Rebuilds [builder] each minute from a [MinuteClock]; only this subtree
/// repaints, not the screen around it.
class MinuteTickerBuilder extends StatelessWidget {
  const MinuteTickerBuilder({super.key, required this.builder, this.clock});

  final Widget Function(BuildContext context, DateTime now) builder;

  /// Defaults to [MinuteClock.shared].
  final MinuteClock? clock;

  @override
  Widget build(BuildContext context) {
    final source = clock ?? MinuteClock.shared;
    return ValueListenableBuilder<DateTime>(
      valueListenable: source,
      builder: (context, _, _) => builder(context, source.value),
    );
  }
}

/// "45 phút" since [since], kept current by the shared minute clock. From
/// [warnAfter] on it turns [warnColor] (the theme's error colour by default).
class ElapsedText extends StatelessWidget {
  const ElapsedText({
    super.key,
    required this.since,
    this.style,
    this.warnAfter,
    this.warnColor,
    this.prefix = '',
    this.clock,
  });

  final DateTime since;
  final TextStyle? style;
  final Duration? warnAfter;
  final Color? warnColor;
  final String prefix;
  final MinuteClock? clock;

  @override
  Widget build(BuildContext context) => MinuteTickerBuilder(
    clock: clock,
    builder: (context, now) {
      final elapsed = now.difference(since);
      final late = warnAfter != null && elapsed >= warnAfter!;
      final base = style ?? DefaultTextStyle.of(context).style;
      return Text(
        '$prefix${formatElapsed(elapsed)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: late
            ? base.copyWith(
                color: warnColor ?? Theme.of(context).colorScheme.error,
              )
            : base,
      );
    },
  );
}
