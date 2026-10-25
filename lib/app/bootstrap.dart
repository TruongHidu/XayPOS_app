import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/environment.dart';
import 'startup_configuration_error_app.dart';

Future<void> bootstrap(Widget app) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Environment.load();
  } on EnvironmentLoadException {
    runApp(StartupConfigurationErrorApp(onRetry: () => bootstrap(app)));
    return;
  }
  runApp(ProviderScope(child: app));
}
