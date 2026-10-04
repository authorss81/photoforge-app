import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/controller.dart';
import 'l10n/app_localizations.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = ResizeController();
  await controller.settings.load();
  runApp(PixelForgeApp(controller: controller));
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
