import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/controller.dart';
import '../core/presets.dart';
import '../l10n/app_localizations.dart';
import 'theme.dart';

/// First-run introduction: three screens explaining what the app does, why it
/// being offline matters, and how to start.
///
/// Shown once and never again. "Never again" is enforced by a flag rather than
/// by a heuristic, so a user who dismissed it does not see it on the next
/// launch, and a test can assert exactly that.
class Onboarding extends StatefulWidget {
  const Onboarding({super.key, required this.controller});

  final ResizeController controller;

  /// True once the user has seen the whole thing. Exposed so the host can
  /// assert it without reaching into storage.
  static Future<bool> isComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_flagKey) ?? false;
    } catch (_) {
      // If storage is unavailable, do not trap the user in onboarding.
      return true;
    }
  }

  static Future<void> markComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_flagKey, true);
    } catch (_) {
      // Nothing to do; the worst case is being asked once more.
    }
  }

  static const String _flagKey = 'pixelforge.onboarding.complete';

  /// Shows onboarding unless it has been completed.
  static Future<void> maybeShow(
    BuildContext context,
    ResizeController controller,
  ) async {
    if (await isComplete()) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Onboarding(controller: controller),
    );
  }

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  int _page = 0;

  static const _pages = 3;

  bool get _isLast => _page == _pages - 1;

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    setState(() => _page++);
  }

  void _back() {
    if (_page == 0) return;
    setState(() => _page--);
  }

  /// Dismissible on every screen, and the choice is remembered either way.
  Future<void> _finish() async {
    await Onboarding.markComplete();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final title = switch (_page) {
      0 => l10n.onboardingTitle1,
      1 => l10n.onboardingTitle2,
      _ => l10n.onboardingTitle3,
    };
    final body = switch (_page) {
      0 => l10n.onboardingBody1,
      1 => l10n.onboardingBody2,
      _ => l10n.onboardingBody3,
    };
    final icon = switch (_page) {
      0 => Icons.photo_library_outlined,
      1 => Icons.wifi_off,
      _ => Icons.tune,
    };

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Icon(
                      icon,
                      size: 30,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  TextButton(
                    onPressed: _finish,
                    child: Text(l10n.onboardingSkip),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_isLast) _PresetPicker(controller: widget.controller),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  for (var i = 0; i < _pages; i++)
                    Container(
                      width: i == _page ? 18 : 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: i == _page
                            ? theme.colorScheme.primary
                            : theme.dividerColor,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  const Spacer(),
                  if (_page > 0)
                    TextButton(
                      onPressed: _back,
                      child: Text(l10n.onboardingBack),
                    ),
                  const SizedBox(width: AppSpacing.xs),
                  FilledButton(
                    onPressed: _next,
                    child: Text(
                      _isLast ? l10n.onboardingGetStarted : l10n.onboardingNext,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The third screen offers a starting preset, because "choose a preset and go"
/// is only useful if the choice can actually be made here.
class _PresetPicker extends StatelessWidget {
  const _PresetPicker({required this.controller});

  final ResizeController controller;

  /// One from each of the three things a person actually arrives wanting:
  /// share it, keep the quality, make it small.
  static const _offered = ['Web / Card', 'Lossless PNG', 'Max Compress Web'];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final available = <ResizePreset>[
      for (final name in _offered)
        if (Presets.all.where((p) => p.name == name).isNotEmpty)
          Presets.all.firstWhere((p) => p.name == name),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.preset,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final p in available)
              ActionChip(
                label: Text(p.name),
                avatar: const Icon(Icons.bolt, size: 15),
                onPressed: () {
                  controller.settings.applyPreset(p);
                  Navigator.of(context).pop();
                  Onboarding.markComplete();
                },
              ),
          ],
        ),
      ],
    );
  }
}
