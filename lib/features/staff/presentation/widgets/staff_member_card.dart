import 'package:flutter/material.dart';

import '../../domain/entities/staff_member.dart';
import '../../../../core/ui/widgets/status_badge.dart';
import '../../../../app/theme/app_status_colors.dart';

class StaffMemberCard extends StatelessWidget {
  const StaffMemberCard({
    super.key,
    required this.staff,
    required this.actions,
  });

  final StaffMember staff;
  final List<Widget> actions;

  String get _initials {
    final words = staff.name.trim().split(RegExp(r'\s+'));
    if (words.first.isEmpty) return '?';
    final initials = words.length > 1
        ? '${words.first.characters.first}${words.last.characters.first}'
        : words.first.characters.first;
    return initials.toUpperCase();
  }

  String get _lastLogin {
    final date = staff.lastLoginAt?.toLocal();
    if (date == null) return 'Chưa đăng nhập';
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sections = [
                  _identity(context),
                  _access(context),
                  _activity(context),
                ];
                if (constraints.maxWidth >= 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: sections[0]),
                      const SizedBox(width: 32),
                      Expanded(flex: 3, child: sections[1]),
                      const SizedBox(width: 32),
                      Expanded(flex: 3, child: sections[2]),
                    ],
                  );
                }
                if (constraints.maxWidth >= 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      sections[0],
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: sections[1]),
                          const SizedBox(width: 24),
                          Expanded(child: sections[2]),
                        ],
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sections[0],
                    const SizedBox(height: 20),
                    sections[1],
                    const SizedBox(height: 20),
                    sections[2],
                  ],
                );
              },
            ),
          ),
          if (actions.isNotEmpty) ...[
            Divider(height: 1, color: colors.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: actions,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _identity(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: Text(
                  _initials,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  staff.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _ContactLine(icon: Icons.mail_outline, text: staff.email),
        const SizedBox(height: 8),
        _ContactLine(
          icon: Icons.phone_outlined,
          text: staff.phone?.trim().isNotEmpty == true
              ? staff.phone!
              : 'Chưa có số điện thoại',
        ),
      ],
    );
  }

  Widget _access(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Vai trò & trạng thái',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusBadge(
              icon: Icons.badge_outlined,
              label: staff.role.name,
              maxLines: 3,
            ),
            StatusBadge(
              icon: staff.active
                  ? Icons.check_circle_outline
                  : Icons.block_outlined,
              label: staff.active ? 'Hoạt động' : 'Đã vô hiệu hóa',
              tone: staff.active ? AppTone.success : AppTone.danger,
            ),
          ],
        ),
      ],
    );
  }

  Widget _activity(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Đăng nhập cuối',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        _ContactLine(icon: Icons.schedule_outlined, text: _lastLogin),
      ],
    );
  }
}

class _ContactLine extends StatelessWidget {
  const _ContactLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
