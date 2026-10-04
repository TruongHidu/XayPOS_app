import 'package:flutter/material.dart';

/// A dialog that uses the available screen width with a small outer margin.
class ResponsiveDialog extends StatelessWidget {
  const ResponsiveDialog({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
          ),
          child: child,
        ),
      ),
    );
  }
}
