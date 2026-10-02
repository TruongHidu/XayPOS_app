import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../app/providers.dart';
import '../controllers/auth_state.dart';
import '../controllers/login_form_controller.dart';
import '../widgets/brand_logo.dart';
import '../widgets/login_form.dart';
import '../widgets/support_footer.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _horizontalPadding = 20.0;
  static const _inlineFooterMinWidth = 370.0;

  late final LoginFormController _formController;

  @override
  void initState() {
    super.initState();
    _formController = LoginFormController();
  }

  @override
  void dispose() {
    _formController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    final controller = ref.read(authControllerProvider);
    await controller.login(_formController.credentials);
    if (mounted && controller.state.status == AuthStatus.authenticated) {
      _formController.clearPassword();
      TextInput.finishAutofillContext();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).state;
    final loginError = authState.failureStage == AuthFailureStage.login
        ? authState.message
        : null;
    final isLoading = authState.status == AuthStatus.authenticating;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final footerWidth = constraints.maxWidth - 2 * _horizontalPadding;
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final stackFooterActions =
                footerWidth < _inlineFooterMinWidth * textScale.clamp(1, 1.5);

            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(
                horizontal: _horizontalPadding,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 55),
                      const AppLogo(size: 72),
                      const SizedBox(height: 42),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: AutofillGroup(
                          child: LoginForm(
                            controller: _formController,
                            isLoading: isLoading,
                            emailError: authState.fieldErrors['email'],
                            passwordError: authState.fieldErrors['password'],
                            generalError: loginError,
                            onLogin: _login,
                          ),
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: SupportFooter(
                          onCall: () => _showMessage('Hotline: 1900 6522'),
                          onChat: () =>
                              _showMessage('Mở trò chuyện với Xây POS.'),
                          stackActions: stackFooterActions,
                        ),
                      ),
                      const SizedBox(height: 27),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
