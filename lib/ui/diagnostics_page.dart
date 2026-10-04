import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/diagnostics/crash_log.dart';
import '../l10n/app_localizations.dart';
import 'theme.dart';

/// Shows the local crash log, with a copy action and a clear button.
///
/// There is no telemetry. Nothing is uploaded by this app or by this page; the
/// copy action puts the log on the clipboard for the user to paste into a bug
/// report, which is their decision to make, not ours.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key, this.log});

  /// Overridable so a test can supply a log rooted in a temp directory rather
  /// than the real support directory.
  final CrashLog? log;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  CrashLog get _log => widget.log ?? crashLog;

  // Re-run on every rebuild rather than cached in a field: the log changes
  // underneath the page while it is open, and a stale copy shown next to a
  // refresh button is worse than no caching at all.
  Future<void> get _loaded => _log.flush();

  Future<void> _refresh() async {
    await _log.flush();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.diagnostics),
        actions: [
          IconButton(
            tooltip: l10n.diagnosticsCopy,
            onPressed: _copy,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: l10n.diagnosticsClear,
            onPressed: _confirmClear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _loaded,
        builder: (context, _) {
          final text = _log.readAll();
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const _PrivacyNotice(),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Text(
                    l10n.diagnosticsSize(_log.totalBytes),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(l10n.diagnosticsRefresh),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (text.trim().isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Center(
                    child: Text(
                      l10n.diagnosticsEmpty,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: SelectableText(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Copies the log for the user to paste into a bug report.
  ///
  /// The clipboard rather than a share sheet on purpose: a share plugin can send
  /// files anywhere, which is exactly the capability this app refuses to take
  /// on. Pasting is something the user does deliberately, into somewhere they
  /// chose.
  Future<void> _copy() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await _log.flush();
    try {
      await Clipboard.setData(ClipboardData(text: _log.toShareJson()));
      messenger.showSnackBar(SnackBar(content: Text(l10n.diagnosticsCopied)));
    } on Object {
      // Report the failure rather than appearing to have copied something.
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.diagnosticsCopyFailed)),
      );
    }
  }

  /// Clearing destroys data, so it asks first.
  Future<void> _confirmClear() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.diagnosticsClear),
        content: Text(l10n.diagnosticsClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.diagnosticsClear),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _log.clear();
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.diagnosticsCleared)));
  }
}

/// States exactly what is recorded. This is not decoration: the product's
/// claim is that nothing identifying leaves the device, and that claim covers
/// the diagnostics file too.
class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline,
            size: 18,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l10n.diagnosticsPrivacy,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
