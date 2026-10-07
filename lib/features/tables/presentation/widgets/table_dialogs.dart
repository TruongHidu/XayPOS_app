import '../../../../core/ui/formatters/local_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/ui/widgets/responsive_dialog.dart';

Future<T?> showTableDialog<T>(
  BuildContext context,
  WidgetRef ref, {
  required String permission,
  required Widget child,
}) {
  final session = ref.read(authControllerProvider).state.session;
  if (!AccessPolicy.canTables(session, permission)) return Future.value();
  final scope = AccessPolicy.tableScope(session);
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        TableScopeGuard(scope: scope, permission: permission, child: child),
  );
}

class TableScopeGuard extends ConsumerWidget {
  const TableScopeGuard({
    super.key,
    required this.scope,
    required this.permission,
    required this.child,
  });
  final Object? scope;
  final String permission;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (AccessPolicy.tableScope(session) != scope ||
        !AccessPolicy.canTables(session, permission)) {
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && route != null && route.isActive) {
          Navigator.of(context).removeRoute(route);
        }
      });
      return const SizedBox.shrink();
    }
    return child;
  }
}

class TableFormLayout extends StatelessWidget {
  const TableFormLayout({
    super.key,
    required this.title,
    required this.children,
    required this.busy,
    required this.onSubmit,
    this.submitLabel = 'Lưu thay đổi',
    this.showSubmit = true,
  });
  final String title;
  final List<Widget> children;
  final bool busy;
  final VoidCallback? onSubmit;
  final String submitLabel;
  final bool showSubmit;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: ResponsiveDialog(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: busy ? null : () => Navigator.of(context).pop(),
                  tooltip: 'Đóng',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AbsorbPointer(
              absorbing: busy,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Đóng'),
                ),
                if (showSubmit)
                  FilledButton(
                    onPressed: busy ? null : onSubmit,
                    child: busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(submitLabel),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

bool tableNeedsReload(Failure? failure) =>
    failure?.code == 'CONCURRENT_TABLE_UPDATE' ||
    failure?.type == FailureType.notFound ||
    failure?.isNetwork == true ||
    failure?.code == 'TABLE_ALREADY_OCCUPIED' ||
    failure?.code == 'TABLE_HAS_OPEN_SESSION' ||
    failure?.code == 'INVALID_TABLE_SESSION_TRANSITION';

class TableFailurePanel extends StatelessWidget {
  const TableFailurePanel({
    super.key,
    required this.failure,
    this.onReload,
    this.reloadLabel = 'Tải lại dữ liệu',
  });
  final Failure? failure;
  final VoidCallback? onReload;
  final String reloadLabel;
  @override
  Widget build(BuildContext context) {
    if (failure == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              failure!.message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
            if (onReload != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onReload,
                  child: Text(reloadLabel),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmTableDraftReload(
  BuildContext context,
  WidgetRef ref,
  String permission,
) async =>
    await showTableDialog<bool>(
      context,
      ref,
      permission: permission,
      child: AlertDialog(
        title: const Text('Thay thế bản đang sửa?'),
        content: const Text(
          'Tải lại sẽ thay nội dung bạn đang sửa bằng dữ liệu mới nhất từ máy chủ.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('Giữ bản nháp'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Thay thế bản nháp'),
          ),
        ],
      ),
    ) ??
    false;

InputDecoration tableField(String label, {String? helper, String? error}) =>
    InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 4,
      errorMaxLines: 4,
      border: const OutlineInputBorder(),
      errorText: error,
    );

String tableDate(DateTime value) => formatLocalDate(value);
