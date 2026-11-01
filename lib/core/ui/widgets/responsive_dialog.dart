import 'package:flutter/material.dart';

/// Dialogs rise from the bottom on phones, within reach of the thumb.
Alignment? phoneDialogAlignment(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600 ? Alignment.bottomCenter : null;

/// A dialog that uses the available screen width with a small outer margin.
class ResponsiveDialog extends StatelessWidget {
  const ResponsiveDialog({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      alignment: phoneDialogAlignment(context),
      insetPadding: EdgeInsets.fromLTRB(16, 24, 16, compact ? 12 : 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.all(compact ? 16 : 24),
          child: child,
        ),
      ),
    );
  }
}
