import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/controller.dart';
import 'core/diagnostics/crash_log.dart';
import 'l10n/app_localizations.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installCrashHandlers();
  final controller = ResizeController();
  await controller.settings.load();
  runApp(PixelForgeApp(controller: controller));
}

/// Routes uncaught errors to the local log.
///
/// Both handlers are needed and they cover different failures:
/// `FlutterError.onError` catches anything thrown during build, layout and
/// paint, and `PlatformDispatcher.onError` catches uncaught async errors that
/// never touch the framework.
///
/// Each forwards to the previously installed handler as well, so this adds
/// logging without swallowing the default reporting. A logging failure must
/// never replace the error the user would otherwise have seen.
void _installCrashHandlers() {
  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    crashLog.recordFlutterError(details);
    previousFlutterHandler?.call(details);
  };

  final previousPlatformHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    crashLog.recordPlatformError(error, stack);
    // Returning false lets the default handler run, which prints to stderr.
    return previousPlatformHandler?.call(error, stack) ?? false;
  };
}

class PixelForgeApp extends StatelessWidget {
  const PixelForgeApp({super.key, required this.controller});

  final ResizeController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PixelForge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomePage(controller: controller),
    );
  }
}
