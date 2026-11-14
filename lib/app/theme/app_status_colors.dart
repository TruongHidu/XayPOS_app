import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The meaning a badge, tile or highlight carries. Features map their own
/// statuses (order, stock, staff...) to a tone; the theme decides the colours.
enum AppTone {
  neutral,
  primary,
  success,
  warning,
  danger,
  info,

  /// Category hues for charts and chips that need more distinct colours than
  /// the statuses above; never to signal success, warning or danger.
  orange,
  cyan,
  violet,
  indigo,
}

/// Colours for one [AppTone]: [foreground] for icons and small text, readable
/// on [background]; [border] outlines the soft area.
@immutable
class ToneColors {
  const ToneColors({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground, background, border;

  static ToneColors lerp(ToneColors a, ToneColors b, double t) => ToneColors(
    foreground: Color.lerp(a.foreground, b.foreground, t)!,
    background: Color.lerp(a.background, b.background, t)!,
    border: Color.lerp(a.border, b.border, t)!,
  );

  @override
  bool operator ==(Object other) =>
      other is ToneColors &&
      other.foreground == foreground &&
      other.background == background &&
      other.border == border;

  @override
  int get hashCode => Object.hash(foreground, background, border);
}

/// Tone colours as a [ThemeExtension], so a dark theme only has to supply a
/// second instance. Read them with `context.tone(AppTone.success)`.
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors(this._tones);

  final Map<AppTone, ToneColors> _tones;

  ToneColors of(AppTone tone) => _tones[tone] ?? light._tones[tone]!;

  static const light = AppStatusColors({
    AppTone.neutral: ToneColors(
      foreground: AppColors.grey700,
      background: AppColors.grey100,
      border: AppColors.grey200,
    ),
    AppTone.primary: ToneColors(
      foreground: AppColors.primaryDark,
      background: AppColors.primarySoft,
      border: AppColors.primaryBorder,
    ),
    AppTone.success: ToneColors(
      foreground: AppColors.success,
      background: AppColors.successSoft,
      border: AppColors.successBorder,
    ),
    AppTone.warning: ToneColors(
      foreground: AppColors.warning,
      background: AppColors.warningSoft,
      border: AppColors.warningBorder,
    ),
    AppTone.danger: ToneColors(
      foreground: AppColors.dangerStrong,
      background: AppColors.dangerSoft,
      border: AppColors.dangerBorder,
    ),
    AppTone.info: ToneColors(
      foreground: AppColors.infoStrong,
      background: AppColors.infoSoft,
      border: AppColors.infoBorder,
    ),
    AppTone.orange: ToneColors(
      foreground: AppColors.accentOrangeStrong,
      background: AppColors.accentOrangeSoft,
      border: AppColors.accentOrangeSoft,
    ),
    AppTone.cyan: ToneColors(
      foreground: AppColors.accentCyan,
      background: AppColors.accentCyanSoft,
      border: AppColors.accentCyanSoft,
    ),
    AppTone.violet: ToneColors(
      foreground: AppColors.accentViolet,
      background: AppColors.accentVioletSoft,
      border: AppColors.accentVioletSoft,
    ),
    AppTone.indigo: ToneColors(
      foreground: AppColors.accentIndigo,
      background: AppColors.accentIndigoSoft,
      border: AppColors.accentIndigoSoft,
    ),
  });

  // TODO(dark-mode): add `static const dark = AppStatusColors({...})` and
  // register it on `AppTheme.dark` once a dark theme ships.

  @override
  AppStatusColors copyWith({Map<AppTone, ToneColors>? tones}) =>
      AppStatusColors({..._tones, ...?tones});

  @override
  AppStatusColors lerp(AppStatusColors? other, double t) {
    if (other == null) return this;
    return AppStatusColors({
      for (final tone in AppTone.values)
        tone: ToneColors.lerp(of(tone), other.of(tone), t),
    });
  }
}

extension AppStatusColorsContext on BuildContext {
  /// Colours of [tone] from the current theme.
  ToneColors tone(AppTone tone) =>
      (Theme.of(this).extension<AppStatusColors>() ?? AppStatusColors.light).of(
        tone,
      );
}
