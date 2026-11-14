import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';

/// The yes/no question of the app ("Huỷ đơn?", "Xoá món?"). Destructive
/// questions colour the confirm button red.
class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.confirmLabel = 'Xác nhận',
    this.cancelLabel = 'Huỷ',
    this.destructive = false,
    this.icon,
  });

  final String title;
  final String? message;

  /// Shown under [message], e.g. a list of what will change.
  final Widget? content;
  final String confirmLabel, cancelLabel;
  final bool destructive;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: icon == null
          ? null
          : Icon(icon, color: destructive ? colors.error : colors.primary),
      title: Text(title),
      content: message == null && content == null
          ? null
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message != null) Text(message!),
                  if (message != null && content != null)
                    const SizedBox(height: AppSpacing.md),
                  ?content,
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// Shows an [AppConfirmDialog]; true only when the user confirms.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  String confirmLabel = 'Xác nhận',
  String cancelLabel = 'Huỷ',
  bool destructive = false,
  IconData? icon,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AppConfirmDialog(
        title: title,
        message: message,
        content: content,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
        icon: icon,
      ),
    ) ??
    false;
