import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/controller.dart';
import '../../l10n/app_localizations.dart';
import '../theme.dart';

/// Desktop keyboard shortcuts.
///
/// The bindings live in one table, and the shortcuts dialog is generated from
/// that same table. A dialog listing different keys from the ones the app
/// handles is worse than no dialog, so there is deliberately no second source
/// of truth.
class ShortcutHost extends StatelessWidget {
  const ShortcutHost({
    super.key,
    required this.controller,
    required this.child,
    required this.addFiles,
    required this.runBatch,
    required this.saveNow,
    required this.deleteSelected,
    required this.togglePreview,
    required this.focusSearch,
    required this.showShortcuts,
  });

  final ResizeController controller;
  final Widget child;

  /// Actions the shortcuts invoke. Passed in rather than reached for, so the
  /// home page keeps ownership of them and this widget stays testable.
  final VoidCallback addFiles;
  final VoidCallback runBatch;
  final VoidCallback saveNow;
  final VoidCallback deleteSelected;
  final VoidCallback togglePreview;
  final VoidCallback focusSearch;
  final VoidCallback showShortcuts;

  /// True where a keyboard is expected. Phones and tablets have none, so the
  /// bindings are skipped rather than shadowing system gestures.
  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// The table, in the order the dialog lists them.
  static List<ShortcutBinding> bindingsFor({
    required VoidCallback addFiles,
    required VoidCallback runBatch,
    required VoidCallback saveNow,
    required VoidCallback deleteSelected,
    required VoidCallback togglePreview,
    required VoidCallback focusSearch,
    required VoidCallback showShortcuts,
  }) => [
    ShortcutBinding(
      activator: const SingleActivator(LogicalKeyboardKey.keyO, control: true),
      icon: Icons.add_photo_alternate_outlined,
      label: (l) => l.shortcutAddFiles,
      run: (_, _) => addFiles(),
    ),
    ShortcutBinding(
      activator: const SingleActivator(LogicalKeyboardKey.enter, control: true),
      icon: Icons.play_arrow,
      label: (l) => l.shortcutProcess,
      run: (_, _) => runBatch(),
    ),
    ShortcutBinding(
      activator: const SingleActivator(LogicalKeyboardKey.keyS, control: true),
      icon: Icons.save_outlined,
      label: (l) => l.shortcutSave,
      run: (_, _) => saveNow(),
    ),
    ShortcutBinding(
      activator: const SingleActivator(LogicalKeyboardKey.delete),
      icon: Icons.delete_outline,
      label: (l) => l.shortcutDeleteSelection,
      run: (_, _) => deleteSelected(),
    ),
    ShortcutBinding(
      activator: const SingleActivator(LogicalKeyboardKey.keyP, control: true),
      icon: Icons.compare,
      label: (l) => l.shortcutTogglePreview,
      run: (_, _) => togglePreview(),
    ),
    ShortcutBinding(
      activator: const SingleActivator(LogicalKeyboardKey.keyF, control: true),
      icon: Icons.search,
      label: (l) => l.shortcutFocusSearch,
      run: (_, _) => focusSearch(),
    ),
    ShortcutBinding(
      activator: const SingleActivator(LogicalKeyboardKey.slash, control: true),
      icon: Icons.keyboard,
      label: (l) => l.shortcutShowShortcuts,
      run: (_, _) => showShortcuts(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bindings = bindingsFor(
      addFiles: addFiles,
      runBatch: runBatch,
      saveNow: saveNow,
      deleteSelected: deleteSelected,
      togglePreview: togglePreview,
      focusSearch: focusSearch,
      showShortcuts: showShortcuts,
    );

    if (!isDesktop) return child;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        for (final b in bindings) b.activator: ShortcutIntent(b),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ShortcutIntent: CallbackAction<ShortcutIntent>(
            onInvoke: (intent) {
              intent.binding.run(controller, null);
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }

  /// Opens the dialog. Also listed in the menu, since not everyone discovers a
  /// shortcut by pressing it.
  static void showShortcutsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => const _ShortcutsDialog(),
    );
  }
}

/// Carries the binding through the intent system, so [Actions] can run it.
class ShortcutIntent extends Intent {
  const ShortcutIntent(this.binding);

  final ShortcutBinding binding;
}

/// A single shortcut: how it is pressed, what it does, and how it is labelled.
class ShortcutBinding {
  const ShortcutBinding({
    required this.activator,
    required this.label,
    required this.icon,
    required this.run,
  });

  final ShortcutActivator activator;
  final String Function(AppStrings l10n) label;
  final IconData icon;

  /// Called when the shortcut fires. Takes the controller so the table can be
  /// built without one, and keeps [BuildContext] out of it entirely.
  final void Function(ResizeController controller, BuildContext? context) run;

  /// The key names to show in the dialog, derived from the activator so the
  /// label can never drift from the binding.
  List<String> get keyLabels => _describe(activator);

  static List<String> _describe(ShortcutActivator a) {
    final out = <String>[];
    if (a is SingleActivator) {
      if (a.control) out.add('Ctrl');
      if (a.meta) out.add('Cmd');
      if (a.shift) out.add('Shift');
      if (a.alt) out.add('Alt');
      out.add(a.trigger.keyLabel);
    } else if (a is CharacterActivator) {
      if (a.control) out.add('Ctrl');
      if (a.meta) out.add('Cmd');
      if (a.alt) out.add('Alt');
      out.add(a.character.toUpperCase());
    } else {
      // An activator shape added by a future Flutter. Say nothing rather than
      // print something wrong.
      return const ['?'];
    }
    return out;
  }
}

class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.keyboardShortcuts),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final b in ShortcutHost.bindingsFor(
              addFiles: () {},
              runBatch: () {},
              saveNow: () {},
              deleteSelected: () {},
              togglePreview: () {},
              focusSearch: () {},
              showShortcuts: () {},
            ))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(b.icon, size: 17, color: theme.colorScheme.primary),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        b.label(l10n),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _KeyCap(keys: b.keyLabels),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

/// Renders one key name in a small rounded box, as is conventional on desktop.
class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.keys});

  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final k in keys)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                k,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
