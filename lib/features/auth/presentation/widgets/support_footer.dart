import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import 'brand_logo.dart';

/// Brand mark and ways to reach Xây POS under the login form. The website
/// link is left out when no address is configured.
class SupportFooter extends StatelessWidget {
  const SupportFooter({
    super.key,
    required this.phone,
    required this.onCall,
    required this.stackActions,
    this.webLabel,
    this.onWeb,
  });

  /// Shown as typed in the configuration, e.g. "1900 6522".
  final String phone;
  final VoidCallback onCall;
  final bool stackActions;

  /// Host shown for the website, e.g. "xaypos.vn"; null hides the link.
  final String? webLabel;
  final VoidCallback? onWeb;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _FooterAction(
        key: const ValueKey('support-call'),
        icon: Icons.phone,
        text: 'Gọi ',
        highlightedText: phone,
        semanticsLabel: 'Gọi hotline $phone',
        onTap: onCall,
      ),
      if (webLabel != null && onWeb != null)
        _FooterAction(
          key: const ValueKey('support-web'),
          icon: Icons.language,
          text: '',
          highlightedText: webLabel,
          semanticsLabel: 'Mở trang web $webLabel',
          onTap: onWeb!,
        ),
    ];

    return Column(
      children: [
        const XayPosWordmark(),
        const SizedBox(height: 25),
        if (stackActions || actions.length == 1)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 6,
            children: actions,
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              actions.first,
              Container(
                width: 1,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: AppColors.grey200,
              ),
              actions.last,
            ],
          ),
      ],
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({
    super.key,
    required this.icon,
    required this.text,
    required this.semanticsLabel,
    required this.onTap,
    this.highlightedText,
  });

  final IconData icon;
  final String text;
  final String? highlightedText;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.grey500),
              const SizedBox(width: 7),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    text: text,
                    children: [
                      if (highlightedText != null)
                        TextSpan(
                          text: highlightedText,
                          style: const TextStyle(
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.primary,
                          ),
                        ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.grey900,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
