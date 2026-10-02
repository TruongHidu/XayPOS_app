import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import 'brand_logo.dart';

class SupportFooter extends StatelessWidget {
  const SupportFooter({
    super.key,
    required this.onCall,
    required this.onChat,
    required this.stackActions,
  });

  final VoidCallback onCall;
  final VoidCallback onChat;
  final bool stackActions;

  @override
  Widget build(BuildContext context) {
    final callAction = _FooterAction(
      icon: Icons.phone,
      text: 'Gọi ',
      highlightedText: '1900 6522',
      onTap: onCall,
    );
    final chatAction = _FooterAction(
      icon: Icons.chat,
      text: 'Chat với Xây POS',
      onTap: onChat,
    );

    return Column(
      children: [
        const XayPosWordmark(),
        const SizedBox(height: 25),
        if (stackActions)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 6,
            children: [callAction, chatAction],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              callAction,
              Container(
                width: 1,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: const Color(0xFFE3E5E8),
              ),
              chatAction,
            ],
          ),
      ],
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({
    required this.icon,
    required this.text,
    required this.onTap,
    this.highlightedText,
  });

  final IconData icon;
  final String text;
  final String? highlightedText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF656970)),
            const SizedBox(width: 7),
            Text.rich(
              TextSpan(
                text: text,
                children: [
                  if (highlightedText != null)
                    TextSpan(
                      text: highlightedText,
                      style: const TextStyle(color: AppTheme.primaryColor),
                    ),
                ],
              ),
              style: const TextStyle(color: Color(0xFF24272C), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
