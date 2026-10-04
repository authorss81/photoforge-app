import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/engine.dart';
import '../core/job.dart';
import '../core/picker.dart';
import '../core/resize_mode.dart';
import '../core/settings.dart';
import '../core/shared_content.dart';
import '../l10n/app_localizations.dart';
import 'diagnostics_page.dart';
import 'onboarding.dart';
import 'theme.dart';
import 'widgets/preview.dart';
import 'widgets/queue_view.dart';
import 'widgets/shortcuts.dart';
import 'widgets/settings_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final ResizeController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _pane = 0;
  bool _dragging = false;

  /// Owned here rather than inside the preview pane so a shortcut can reach it
  /// without a GlobalKey.
  final GlobalKey<_PreviewPaneState> _previewKey = GlobalKey();

  ResizeController get controller => widget.controller;

  static const _wideBreakpoint = 980.0;

  @override
  void initState() {
    super.initState();
    _collectShared();
    // Deferred to after the first frame: maybeShow awaits storage, and showing a
    // dialog during initState would run before there is anything to show it
    // over.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Onboarding.maybeShow(context, controller);
    });
  }

  /// The actions the shortcuts invoke. Public methods on the state rather than
  /// inline closures, so a widget test can trigger them through the same path a
  /// key press takes.
  void togglePreview() => _previewKey.currentState?.toggleView();

  void deleteSelected() {
    final id = controller.selectedId;
    if (id != null) controller.removeJob(id);
  }

  void showShortcuts() => ShortcutHost.showShortcutsDialog(context);

  void _openDiagnostics() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DiagnosticsPage()));
  }

  void focusSearch() {
    // There is no settings search field yet (deliberately out of scope for this
    // phase). Jump to the settings pane so the shortcut is honest about where
    // the user lands rather than silently doing nothing.
    if (_pane != 2) setState(() => _pane = 2);
  }

  /// Picks up images shared into the app while it was closed. Runs once at
  /// startup and never again; shares arriving while running are rare enough
  /// that relaunching to collect them is acceptable.
  Future<void> _collectShared() async {
    try {
      final shared = await SharedContent.collect();
      if (shared == null || shared.isEmpty || !mounted) return;
      controller.addDroppedFiles(shared);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added ${shared.length} shared file${shared.length == 1 ? '' : 's'}',
          ),
        ),
      );
    } catch (_) {
      // Sharing is a convenience; it must never break startup.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Outside the AnimatedBuilder: the shortcut layer must not be rebuilt on
    // every queue change, and a rebuild would drop the focus the keys need.
    return ShortcutHost(
      controller: controller,
      addFiles: controller.busy ? () {} : _addFiles,
      runBatch: _startBatch,
      saveNow: _saveNow,
      deleteSelected: deleteSelected,
      togglePreview: togglePreview,
      focusSearch: focusSearch,
      showShortcuts: showShortcuts,
      child: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: _onDrop,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return Scaffold(
              appBar: _buildAppBar(context),
              body: Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= _wideBreakpoint;
                      return wide ? _buildWide() : _buildNarrow();
                    },
                  ),
                  if (_dragging) const _DropOverlay(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _startBatch() {
    if (controller.busy) return;
    controller.runBatch();
  }

  /// Writes finished jobs to the chosen folder now, rather than waiting for
  /// the write-immediately setting to do it at the end of a batch.
  Future<void> _saveNow() async {
    final done = controller.jobs.where(
      (j) => j.status == JobStatus.done && j.output != null,
    );
    if (done.isEmpty) return;
    await controller.saveAll();
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(
              Icons.crop_free_rounded,
              size: 17,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            AppLocalizations.of(context).appName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(width: AppSpacing.md),
          Tooltip(
            message: AppLocalizations.of(context).offlineTooltip,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 12,
                    color: Colors.green.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    AppLocalizations.of(context).offline,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: AppLocalizations.of(context).addImages,
          onPressed: controller.busy ? null : _addFiles,
          icon: const Icon(Icons.add_photo_alternate_outlined),
        ),
        // No save button. Settings autosave on a 400ms debounce, so a button
        // would imply unsaved work that cannot exist, and a user who closes the
        // app immediately after a change would reasonably expect it kept. The
        // confirmation appears on its own once the write lands.
        _SavedIndicator(
          generation: controller.settings.savedGeneration,
          label: AppLocalizations.of(context).settingsSaved,
        ),
        if (ShortcutHost.isDesktop)
          IconButton(
            tooltip: AppLocalizations.of(context).keyboardShortcuts,
            onPressed: showShortcuts,
            icon: const Icon(Icons.keyboard_outlined),
          ),
        // Always present, on every platform: a crash log the user cannot reach
        // is not a diagnostic tool.
        IconButton(
          tooltip: AppLocalizations.of(context).diagnostics,
          onPressed: _openDiagnostics,
          icon: const Icon(Icons.bug_report_outlined),
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(height: 0.5, color: theme.dividerColor),
      ),
    );
  }

  Widget _buildWide() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 330,
          child: Card(
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.fromLTRB(12, 12, 6, 12),
            child: QueueView(controller: controller),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _PreviewPane(key: _previewKey, controller: controller),
          ),
        ),
        SizedBox(
          width: 360,
          child: Card(
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.fromLTRB(6, 12, 12, 12),
            child: Column(
              children: [
                const PaneHeader('Output settings', icon: Icons.tune),
                Expanded(child: SettingsView(controller: controller)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrow() {
    return Column(
      children: [
        Expanded(
          child: IndexedStack(
            index: _pane,
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                child: QueueView(controller: controller),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                child: _PreviewPane(key: _previewKey, controller: controller),
              ),
              Card(
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                child: Column(
                  children: [
                    PaneHeader(
                      AppLocalizations.of(context).outputSettings,
                      icon: Icons.tune,
                    ),
                    Expanded(child: SettingsView(controller: controller)),
                  ],
                ),
              ),
            ],
          ),
        ),
        NavigationBar(
          height: 62,
          selectedIndex: _pane,
          onDestinationSelected: (i) => setState(() => _pane = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.photo_library_outlined),
              selectedIcon: const Icon(Icons.photo_library),
              label: AppLocalizations.of(context).queue,
            ),
            NavigationDestination(
              icon: const Icon(Icons.preview_outlined),
              selectedIcon: const Icon(Icons.preview),
              label: AppLocalizations.of(context).preview,
            ),
            NavigationDestination(
              icon: const Icon(Icons.tune_outlined),
              selectedIcon: const Icon(Icons.tune),
              label: AppLocalizations.of(context).settings,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addFiles() async {
    await controller.addViaPicker();
  }

  Future<void> _onDrop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    final files = <({String name, Uint8List bytes, String? path})>[];
    await _collect(details.files, files, 0);
    if (files.isEmpty || !mounted) return;

    controller.addDroppedFiles(files);
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          files.length == 1 ? l10n.fileAdded : l10n.filesAdded(files.length),
        ),
      ),
    );
  }

  /// Flattens dropped items, walking into directories up to 3 levels deep.
  Future<void> _collect(
    List<DropItem> items,
    List<({String name, Uint8List bytes, String? path})> out,
    int depth,
  ) async {
    if (depth > 3 || out.length >= 400) return;
    for (final item in items) {
      if (item is DropItemDirectory) {
        await _collect(item.children, out, depth + 1);
        continue;
      }
      final ext = ResizeEngine.extensionOfName(item.name) ?? '';
      if (!supportedInputExtensions.contains(ext)) continue;
      try {
        final bytes = await item.readAsBytes();
        if (bytes.isEmpty || bytes.lengthInBytes > SourcePicker.maxFileBytes) {
          continue;
        }
        out.add((name: item.name, bytes: bytes, path: item.path));
      } catch (_) {
        continue;
      }
    }
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Container(
        color: scheme.primary.withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 26),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.primary, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.file_download_outlined,
                size: 42,
                color: scheme.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                AppLocalizations.of(context).dropToAdd,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppLocalizations.of(context).dropDepthHint,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewPane extends StatefulWidget {
  const _PreviewPane({super.key, required this.controller});

  final ResizeController controller;

  @override
  State<_PreviewPane> createState() => _PreviewPaneState();
}

enum _PreviewMode { before, split, after }

class _PreviewPaneState extends State<_PreviewPane> {
  _PreviewMode _view = _PreviewMode.split;
  Uint8List? _liveBytes;
  String? _liveForJob;
  int _generation = 0;
  Timer? _debounce;

  /// Cycles before -> split -> after. Public so the toggle shortcut can reach
  /// it through the state key rather than duplicating the order here.
  void toggleView() {
    setState(() {
      _view = switch (_view) {
        _PreviewMode.before => _PreviewMode.split,
        _PreviewMode.split => _PreviewMode.after,
        _PreviewMode.after => _PreviewMode.before,
      };
    });
    _scheduleLive();
  }

  @override
  void initState() {
    super.initState();
    widget.controller.settings.addListener(_scheduleLive);
    widget.controller.addListener(_scheduleLive);
    _scheduleLive();
  }

  @override
  void didUpdateWidget(_PreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.settings.removeListener(_scheduleLive);
      oldWidget.controller.removeListener(_scheduleLive);
      widget.controller.settings.addListener(_scheduleLive);
      widget.controller.addListener(_scheduleLive);
      _scheduleLive();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.settings.removeListener(_scheduleLive);
    widget.controller.removeListener(_scheduleLive);
    super.dispose();
  }

  /// Regenerates the live preview 120ms after the last change, so a slider
  /// drag queues one render instead of dozens. A newer request discards the
  /// older result rather than flashing it.
  void _scheduleLive() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _renderLive);
  }

  Future<void> _renderLive() async {
    final controller = widget.controller;
    final job = controller.selected;
    if (job == null || !job.hasSource || _view == _PreviewMode.before) return;
    final generation = ++_generation;
    final jobId = job.id;
    final snapshot = controller.settings.toJson();
    final previewSettings = ResizeSettings()..loadFrom(snapshot);
    final bytes = await ResizeEngine.renderPreview(
      job.bytes,
      previewSettings,
      name: job.name,
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _liveBytes = bytes;
      _liveForJob = jobId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final job = controller.selected;
    final theme = Theme.of(context);

    final live =
        _view != _PreviewMode.before &&
        job != null &&
        _liveForJob == job.id &&
        _liveBytes != null;
    final original = job == null
        ? null
        : (job.hasSource ? job.bytes : job.thumbnail);
    final processed = job == null
        ? null
        : (live
              ? _liveBytes
              : (job.output ?? (job.hasSource ? job.bytes : job.thumbnail)));
    final l10n = AppLocalizations.of(context);
    final label = job == null
        ? null
        : (_view == _PreviewMode.before
              ? l10n.original
              : (live
                    ? l10n.live
                    : (job.output != null ? l10n.result : l10n.preview)));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaneHeader(
            job?.name ?? l10n.preview,
            icon: Icons.preview_outlined,
            subtitle: job == null
                ? l10n.nothingSelected
                : '${job.sourceSizeLabel}  ·  ${formatBytes(job.inputBytes)}',
            trailing: job == null
                ? null
                : SegmentedButton<_PreviewMode>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      ButtonSegment(
                        value: _PreviewMode.before,
                        label: Text(
                          l10n.before,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      ButtonSegment(
                        value: _PreviewMode.split,
                        label: Text(
                          l10n.split,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      ButtonSegment(
                        value: _PreviewMode.after,
                        label: Text(
                          l10n.after,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                    selected: {_view},
                    onSelectionChanged: (s) {
                      setState(() => _view = s.first);
                      _scheduleLive();
                    },
                  ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: LargePreview(
                before: original,
                after: _view == _PreviewMode.before ? original : processed,
                split: _view == _PreviewMode.split,
                label: label,
              ),
            ),
          ),
          if (job != null) _ResultBar(job: job, controller: controller),
          if (job == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                AppLocalizations.of(context).addImagesEmpty,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultBar extends StatelessWidget {
  const _ResultBar({required this.job, required this.controller});

  final ImageJob job;
  final ResizeController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final s = controller.settings;
    final predicted = computeTargetSize(
      s.spec,
      job.sourceWidth ?? 0,
      job.sourceHeight ?? 0,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Stat(label: l10n.target, value: '$predicted', icon: Icons.crop),
          _Stat(
            label: l10n.format,
            value: job.output != null
                ? _extOf(job)
                : (s.format == OutputFormat.keep
                      ? l10n.keepFormat
                      : s.format.extension!.toUpperCase()),
            icon: Icons.description_outlined,
          ),
          if (job.output != null)
            _Stat(
              label: l10n.sizeLabel,
              value: formatBytes(job.outputBytes),
              icon: Icons.sd_storage_outlined,
              highlight: true,
            ),
          if (job.output != null)
            _Stat(
              label: l10n.qualityLabel,
              value: job.solvedQuality?.toString() ?? l10n.lossless,
              icon: Icons.tune,
            ),
          if (job.savedRatio != null && job.savedRatio! > 0)
            _Stat(
              label: l10n.saved,
              value: '-${(job.savedRatio! * 100).round()}%',
              icon: Icons.savings_outlined,
              highlight: true,
            ),
          if (job.output != null && SharedContent.isMobile)
            IconButton(
              tooltip: l10n.saveToGallery,
              onPressed: () => _saveToGallery(context),
              icon: const Icon(Icons.save_alt_outlined, size: 20),
            ),
        ],
      ),
    );
  }

  Future<void> _saveToGallery(BuildContext context) async {
    final output = job.output;
    if (output == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final error = await SharedContent.saveToGallery(output, job.name);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? l10n.savedToGallery(job.name))),
    );
  }

  static String _extOf(ImageJob job) {
    final src = ResizeEngine.extensionOfName(job.name) ?? 'jpg';
    return src.toUpperCase();
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlight
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Briefly confirms that settings reached disk.
///
/// Driven by `savedGeneration`, which the settings object bumps after each
/// successful write. Keying off that rather than off a local flag means the
/// indicator cannot get out of step with what was actually persisted, and it
/// stays hidden when nothing has changed recently instead of lingering.
class _SavedIndicator extends StatefulWidget {
  const _SavedIndicator({required this.generation, required this.label});

  final int generation;
  final String label;

  @override
  State<_SavedIndicator> createState() => _SavedIndicatorState();
}

class _SavedIndicatorState extends State<_SavedIndicator> {
  bool _visible = false;
  Timer? _hide;

  @override
  void didUpdateWidget(_SavedIndicator old) {
    super.didUpdateWidget(old);
    if (widget.generation == old.generation) return;
    _show();
  }

  void _show() {
    _hide?.cancel();
    setState(() => _visible = true);
    _hide = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 15,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(
            widget.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
