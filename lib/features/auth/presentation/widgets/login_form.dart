import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../controllers/login_form_controller.dart';

class LoginForm extends StatelessWidget {
  const LoginForm({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.onLogin,
    this.emailError,
    this.passwordError,
    this.generalError,
  });

  final LoginFormController controller;
  final bool isLoading;
  final VoidCallback onLogin;
  final String? emailError;
  final String? passwordError;
  final String? generalError;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LoginTextField(
              key: const Key('email-field'),
              controller: controller.emailController,
              focusNode: controller.emailFocusNode,
              hintText: 'Gmail',
              errorText: emailError,
              enabled: !isLoading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              onSubmitted: (_) => controller.focusPassword(),
            ),
            const SizedBox(height: 18),
            _LoginTextField(
              key: const Key('password-field'),
              controller: controller.passwordController,
              focusNode: controller.passwordFocusNode,
              hintText: 'Mật khẩu',
              errorText: passwordError,
              enabled: !isLoading,
              obscureText: controller.obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) {
                if (!isLoading) onLogin();
              },
              suffix: IconButton(
                key: const Key('password-visibility-button'),
                onPressed: isLoading
                    ? null
                    : controller.togglePasswordVisibility,
                tooltip: controller.obscurePassword
                    ? 'Hiện mật khẩu'
                    : 'Ẩn mật khẩu',
                icon: Icon(
                  controller.obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 21,
                  color: const Color(0xFFACB0B8),
                ),
              ),
            ),
            if (generalError != null) ...[
              const SizedBox(height: 14),
              Semantics(
                liveRegion: true,
                child: Text(
                  generalError!,
                  key: const Key('login-error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              height: 48,
              child: FilledButton(
                key: const Key('login-button'),
                onPressed: isLoading ? null : onLogin,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: isLoading
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Đăng nhập'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.enabled,
    required this.textInputAction,
    required this.onSubmitted,
    this.errorText,
    this.focusNode,
    this.obscureText = false,
    this.keyboardType,
    this.autofillHints,
    this.suffix,
  });

  final TextEditingController controller;
  final String hintText;
  final bool enabled;
  final String? errorText;
  final TextInputAction textInputAction;
  final ValueChanged<String> onSubmitted;
  final FocusNode? focusNode;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFD8DBE1), width: 1.2),
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Color(0xFF23262B), fontSize: 16),
      decoration: InputDecoration(
        hintText: hintText,
        errorText: errorText,
        hintStyle: const TextStyle(color: Color(0xFFC5C7CC), fontSize: 16),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        suffixIcon: suffix,
        suffixIconConstraints: suffix == null
            ? null
            : const BoxConstraints(minHeight: 48, minWidth: 48),
        enabledBorder: border,
        disabledBorder: border,
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.error,
            width: 1.3,
          ),
        ),
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(
            color: AppTheme.primaryColor,
            width: 1.3,
          ),
        ),
      ),
    );
  }
}
