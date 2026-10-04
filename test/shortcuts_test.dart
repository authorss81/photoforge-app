import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelforge/core/controller.dart';
import 'package:pixelforge/l10n/app_localizations.dart';
import 'package:pixelforge/ui/widgets/shortcuts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Order matches the dialog.
const _names = [
  'addFiles',
  'runBatch',
  'saveNow',
  'deleteSelected',
  'togglePreview',
  'focusSearch',
  'showShortcuts',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Runs [body] as a Windows-platform test, always clearing the override.
  ///
  /// The override must be cleared inside the test body. The binding asserts no
  /// foundation debug variable is left set when a test ends, and that check runs
  /// before tearDown and before addTearDown, so clearing it in either of those
  /// is too late.
  Future<void> onWindows(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// Builds the real host, with one flag per action so a fired shortcut is
  /// observable. The flags are returned rather than captured so each test owns
  /// its own.
  Future<List<bool>> pumpHost(WidgetTester tester) async {
    final fired = List<bool>.filled(_names.length, false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShortcutHost(
            controller: ResizeController(),
            addFiles: () => fired[0] = true,
            runBatch: () => fired[1] = true,
            saveNow: () => fired[2] = true,
            deleteSelected: () => fired[3] = true,
            togglePreview: () => fired[4] = true,
            focusSearch: () => fired[5] = true,
            // Opens the real dialog, so the tests that check it are reached the
            // way a user reaches it rather than by calling the dialog directly.
            showShortcuts: () {
              fired[6] = true;
              ShortcutHost.showShortcutsDialog(
                tester.element(find.byType(ShortcutHost)),
              );
            },
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fired;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  group('keyboard shortcuts', () {
    testWidgets('every binding fires', (tester) async {
      await onWindows(tester, () async {
        final fired = await pumpHost(tester);

        await press(tester, LogicalKeyboardKey.keyO);
        expect(fired[0], isTrue, reason: 'Ctrl+O must add files');

        await press(tester, LogicalKeyboardKey.enter);
        expect(fired[1], isTrue, reason: 'Ctrl+Enter must process the queue');

        await press(tester, LogicalKeyboardKey.keyS);
        expect(fired[2], isTrue, reason: 'Ctrl+S must save results');

        await press(tester, LogicalKeyboardKey.keyP);
        expect(fired[4], isTrue, reason: 'Ctrl+P must toggle the preview');

        await press(tester, LogicalKeyboardKey.keyF);
        expect(fired[5], isTrue, reason: 'Ctrl+F must focus search');

        await press(tester, LogicalKeyboardKey.slash);
        expect(fired[6], isTrue, reason: 'Ctrl+/ must list the shortcuts');
      });
    });

    testWidgets('Delete fires without a modifier', (tester) async {
      await onWindows(tester, () async {
        final fired = await pumpHost(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pumpAndSettle();
        expect(fired[3], isTrue, reason: 'Delete must remove the selection');
      });
    });

    testWidgets('an unbound key does nothing', (tester) async {
      await onWindows(tester, () async {
        final fired = await pumpHost(tester);
        await press(tester, LogicalKeyboardKey.keyQ);
        expect(fired.any((f) => f), isFalse);
      });
    });

    testWidgets('a binding without its modifier does not fire', (tester) async {
      await onWindows(tester, () async {
        final fired = await pumpHost(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
        await tester.pumpAndSettle();
        expect(
          fired[0],
          isFalse,
          reason: 'plain O must not trigger the add-files shortcut',
        );
      });
    });

    testWidgets('the dialog lists every binding and its keys', (tester) async {
      await onWindows(tester, () async {
        await pumpHost(tester);
        final bindings = _table();
        expect(bindings, hasLength(_names.length));

        // Opened through the shortcut, so the dialog is reached the way a user
        // reaches it.
        await press(tester, LogicalKeyboardKey.slash);
        expect(find.byType(AlertDialog), findsOneWidget);

        final strings = EnStrings();
        for (final b in bindings) {
          expect(
            find.text(b.label(strings)),
            findsOneWidget,
            reason: 'the dialog must list "${b.label(strings)}"',
          );
          for (final key in b.keyLabels) {
            expect(
              find.text(key),
              findsWidgets,
              reason: 'the dialog must show the key $key',
            );
          }
        }
      });
    });

    testWidgets('the dialog closes', (tester) async {
      await onWindows(tester, () async {
        await pumpHost(tester);
        await press(tester, LogicalKeyboardKey.slash);
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text(EnStrings().close));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      });
    });

    testWidgets('no two bindings share an activator', (tester) async {
      // The label and the keys are both derived from one table, so the only way
      // the dialog could lie is a collision making a binding unreachable.
      final bindings = _table();
      final activators = bindings.map((b) => b.activator.toString()).toSet();
      expect(
        activators,
        hasLength(bindings.length),
        reason: 'two bindings share an activator, so one would be unreachable',
      );
    });

    testWidgets('every binding has a label and keys to show', (tester) async {
      final strings = EnStrings();
      for (final b in _table()) {
        expect(b.label(strings), isNotEmpty);
        expect(
          b.keyLabels,
          isNotEmpty,
          reason: 'a binding with no key to show',
        );
      }
    });

    testWidgets('bindings are skipped where there is no keyboard', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final fired = <bool>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ShortcutHost(
                controller: ResizeController(),
                addFiles: () => fired.add(true),
                runBatch: () {},
                saveNow: () {},
                deleteSelected: () {},
                togglePreview: () {},
                focusSearch: () {},
                showShortcuts: () {},
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await press(tester, LogicalKeyboardKey.keyO);
        expect(
          fired,
          isEmpty,
          reason: 'a phone must not register desktop key bindings',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

/// The binding table with no-op actions, for assertions about the table itself.
List<ShortcutBinding> _table() => ShortcutHost.bindingsFor(
  addFiles: () {},
  runBatch: () {},
  saveNow: () {},
  deleteSelected: () {},
  togglePreview: () {},
  focusSearch: () {},
  showShortcuts: () {},
);
