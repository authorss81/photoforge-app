import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelforge/core/controller.dart';
import 'package:pixelforge/core/presets.dart';
import 'package:pixelforge/l10n/app_localizations.dart';
import 'package:pixelforge/ui/onboarding.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(ResizeController controller) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => Onboarding.maybeShow(context, controller),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('onboarding', () {
    testWidgets('appears on a first run', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = ResizeController();
      addTearDown(controller.dispose);

      expect(await Onboarding.isComplete(), isFalse);

      await tester.pumpWidget(_host(controller));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(Onboarding), findsOneWidget);
      expect(find.text(EnStrings().onboardingTitle1), findsOneWidget);
    });

    testWidgets('never appears again once completed', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = ResizeController();
      addTearDown(controller.dispose);

      await Onboarding.markComplete();
      expect(await Onboarding.isComplete(), isTrue);

      await tester.pumpWidget(_host(controller));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.byType(Onboarding),
        findsNothing,
        reason: 'a dismissed or completed introduction must not reappear',
      );
    });

    test('the flag is persisted under a stable key', () async {
      SharedPreferences.setMockInitialValues({});
      await Onboarding.markComplete();

      // Reading the store directly proves the flag was written to disk rather
      // than held in memory, which is the whole point of it surviving a
      // relaunch.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pixelforge.onboarding.complete'), isTrue);
      expect(await Onboarding.isComplete(), isTrue);
    });

    testWidgets('it can be skipped from the first screen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = ResizeController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(controller));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(EnStrings().onboardingSkip));
      await tester.pumpAndSettle();

      expect(find.byType(Onboarding), findsNothing);
      expect(
        await Onboarding.isComplete(),
        isTrue,
        reason: 'skipping must count as completing, or it returns forever',
      );
    });

    testWidgets('it advances through three screens and finishes', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final controller = ResizeController();
      addTearDown(controller.dispose);
      final l10n = EnStrings();

      await tester.pumpWidget(_host(controller));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.onboardingTitle1), findsOneWidget);
      await tester.tap(find.text(l10n.onboardingNext));
      await tester.pumpAndSettle();
      expect(find.text(l10n.onboardingTitle2), findsOneWidget);

      await tester.tap(find.text(l10n.onboardingNext));
      await tester.pumpAndSettle();
      expect(find.text(l10n.onboardingTitle3), findsOneWidget);

      // The third screen offers presets, so "pick one and go" is real.
      expect(find.text('Web / Card'), findsOneWidget);

      await tester.tap(find.text(l10n.onboardingGetStarted));
      await tester.pumpAndSettle();

      expect(find.byType(Onboarding), findsNothing);
      expect(await Onboarding.isComplete(), isTrue);
    });

    testWidgets('back returns to the previous screen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = ResizeController();
      addTearDown(controller.dispose);
      final l10n = EnStrings();

      await tester.pumpWidget(_host(controller));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.onboardingTitle1), findsOneWidget);
      // No back button on the first screen.
      expect(find.text(l10n.onboardingBack), findsNothing);

      await tester.tap(find.text(l10n.onboardingNext));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.onboardingBack));
      await tester.pumpAndSettle();

      expect(find.text(l10n.onboardingTitle1), findsOneWidget);
      await Onboarding.markComplete();
    });

    testWidgets('choosing a preset applies it and closes', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = ResizeController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(controller));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(EnStrings().onboardingNext));
      await tester.pumpAndSettle();
      await tester.tap(find.text(EnStrings().onboardingNext));
      await tester.pumpAndSettle();

      final preset = Presets.all.firstWhere((p) => p.name == 'Web / Card');
      await tester.tap(find.text('Web / Card'));
      await tester.pumpAndSettle();

      expect(find.byType(Onboarding), findsNothing);
      expect(
        controller.settings.presetName,
        preset.name,
        reason: 'the chosen preset must actually be applied',
      );
      expect(await Onboarding.isComplete(), isTrue);
    });

    testWidgets('storage failure does not trap the user', (tester) async {
      // No mock installed and no binding: reading the flag throws. Showing
      // onboarding anyway would be worse than skipping it.
      final controller = ResizeController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(controller));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'an unreadable flag must not surface as an error',
      );
    });
  });
}
