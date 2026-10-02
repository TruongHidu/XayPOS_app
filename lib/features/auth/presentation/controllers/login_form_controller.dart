import 'package:flutter/material.dart';

import '../../domain/entities/login_credentials.dart';

class LoginFormController extends ChangeNotifier {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final emailFocusNode = FocusNode();
  final passwordFocusNode = FocusNode();

  bool _obscurePassword = true;

  bool get obscurePassword => _obscurePassword;

  LoginCredentials get credentials => LoginCredentials(
    email: emailController.text.trim(),
    password: passwordController.text,
  );

  void focusPassword() => passwordFocusNode.requestFocus();

  void clearPassword() => passwordController.clear();

  void togglePasswordVisibility() {
    _obscurePassword = !_obscurePassword;
    notifyListeners();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    super.dispose();
  }
}
