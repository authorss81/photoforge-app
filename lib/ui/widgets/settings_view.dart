import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/controller.dart';
import '../../core/presets.dart';
import '../../core/resize_mode.dart';
import '../../core/settings.dart';
import '../../l10n/app_localizations.dart';
import '../theme.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key, required this.controller});

  final ResizeController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.settings;
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
          children: [
            _presets(context, s),
            SectionLabel(l10n.size),
            _size(context, s),
            _outputFormat(context, s),
            if (s.format.supportsFrames || s.format == OutputFormat.keep)
              _animation(context, s),
            if (s.format.supportsQuality || s.format == OutputFormat.keep)
              _quality(context, s),
            if (s.format == OutputFormat.png) _pngLevel(context, s),
            if (s.format == OutputFormat.webp) _webp(context, s),
            if (s.format == OutputFormat.jpeg || s.format == OutputFormat.keep)
              _chroma(context, s),
            _metadata(context, s),
            SectionLabel(l10n.transform),
            _transform(context, s),
            SectionLabel(l10n.adjust),
            _adjustments(context, s),
            _filters(context, s),
            SectionLabel(l10n.watermark),
            _watermark(context, s),
            SectionLabel(l10n.output),
            _naming(context, s),
            _destination(context, s),
            SectionLabel(l10n.extraOutputs),
            _extraOutputs(context, s),
          ],
        );
      },
    );
  }

  // --------------------------------------------------------------- presets
  Widget _presets(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    final groups = Presets.groups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(l10n.preset),
        DropdownButtonFormField<String>(
          initialValue: s.presetName,
          isExpanded: true,
          hint: Text(AppLocalizations.of(context).custom),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.auto_awesome_outlined, size: 19),
          ),
          items: [
            for (final g in groups) ...[
              DropdownMenuItem<String>(
                enabled: false,
                child: Text(
                  g.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.8,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final p in g.presets)
                DropdownMenuItem<String>(
                  value: p.name,
                  child: Text(
                    p.note.isEmpty ? p.name : '${p.name}  ·  ${p.note}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ],
          onChanged: (v) {
            final p = v == null ? null : Presets.byName(v);
            if (p != null) s.applyPreset(p);
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in <ResizePreset>[
              Presets.optimize[3],
              Presets.optimize[1],
              Presets.social[0],
              Presets.web[0],
              Presets.docs[2],
            ])
              ActionChip(
                label: Text(p.name, style: const TextStyle(fontSize: 11.5)),
                visualDensity: VisualDensity.compact,
                onPressed: () => s.applyPreset(p),
              ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ size
  Widget _size(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    final showPercent = s.mode == ResizeMode.percent;
    final showBox =
        s.mode != ResizeMode.percent && s.mode != ResizeMode.original;
    final showWidth = showBox && s.mode != ResizeMode.height;
    final showHeight = showBox && s.mode != ResizeMode.width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<ResizeMode>(
          initialValue: s.mode,
          decoration: InputDecoration(labelText: l10n.mode),
          items: [
            for (final m in ResizeMode.values)
              DropdownMenuItem(value: m, child: Text(m.label)),
          ],
          onChanged: (v) {
            if (v != null) s.setMode(v);
          },
        ),
        if (showPercent) ...[
          const SizedBox(height: AppSpacing.md),
          _Slider(
            label: l10n.scale,
            value: s.percent.toDouble(),
            min: 1,
            max: 400,
            display: '${s.percent}%',
            onChanged: (v) => s.setPercent(v.round()),
          ),
        ],
        if (showBox) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showWidth)
                Expanded(
                  child: _NumberField(
                    label: l10n.width,
                    value: s.width,
                    onChanged: s.setWidth,
                  ),
                ),
              const SizedBox(width: AppSpacing.sm),
              if (showWidth && showHeight)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: IconButton(
                    tooltip: s.linkDimensions
                        ? l10n.unlinkDimensions
                        : l10n.linkAspect,
                    onPressed: () => s.setLinkDimensions(!s.linkDimensions),
                    icon: Icon(
                      s.linkDimensions ? Icons.link : Icons.link_off,
                      size: 18,
                      color: s.linkDimensions
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ),
              if (showHeight)
                Expanded(
                  child: _NumberField(
                    label: l10n.height,
                    value: s.height,
                    onChanged: s.setHeight,
                  ),
                ),
            ],
          ),
          if (s.mode == ResizeMode.exactFit ||
              s.mode == ResizeMode.exactCrop) ...[
            const SizedBox(height: AppSpacing.sm),
            _PadColorRow(settings: s),
          ],
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: s.allowUpscale,
          onChanged: s.setAllowUpscale,
          title: Text(l10n.allowUpscale, style: TextStyle(fontSize: 13.5)),
          subtitle: Text(
            l10n.allowUpscaleHint,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- output
  Widget _outputFormat(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(l10n.output),
        SegmentedButton<OutputFormat>(
          showSelectedIcon: false,
          segments: [
            for (final f in OutputFormat.values)
              ButtonSegment(
                value: f,
                label: Text(f.extension?.toUpperCase() ?? l10n.keepAllCaps),
              ),
          ],
          selected: {s.format},
          onSelectionChanged: (sel) => s.setFormat(sel.first),
        ),
      ],
    );
  }

  Widget _animation(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: s.preserveAnimation,
      onChanged: s.setPreserveAnimation,
      title: Text(
        AppLocalizations.of(context).preserveAnimation,
        style: TextStyle(fontSize: 13.5),
      ),
      subtitle: Text(
        l10n.preserveAnimationBody,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _quality(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    final kb = s.targetKb;
    final isKb = kb != null && s.format.supportsQuality;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _Slider(
                label: isKb ? l10n.qualityAuto : l10n.quality,
                value: s.quality.toDouble(),
                min: 1,
                max: 100,
                display: s.quality.toString(),
                enabled: !isKb,
                onChanged: (v) => s.setQuality(v.round()),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 118,
              child: _NumberField(
                label: l10n.maxKb,
                value: kb ?? 0,
                allowZeroAsNull: true,
                hint: 'off',
                onChanged: s.setTargetKb,
              ),
            ),
          ],
        ),
        if (isKb)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Quality is solved per image to land under $kb KB.',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _pngLevel(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    return _Slider(
      label: l10n.pngCompression,
      value: s.pngLevel.toDouble(),
      min: 0,
      max: 9,
      display: '${s.pngLevel}',
      onChanged: (v) => s.setPngLevel(v.round()),
    );
  }

  Widget _webp(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: s.webpLossless,
          onChanged: s.setWebpLossless,
          title: Text(
            AppLocalizations.of(context).losslessWebp,
            style: TextStyle(fontSize: 13.5),
          ),
        ),
        if (!s.webpLossless)
          _Slider(
            label: l10n.encodeEffort,
            value: s.webpMethod.toDouble(),
            min: 0,
            max: 6,
            display: s.webpMethod.toString(),
            onChanged: (v) => s.setWebpMethod(v.round()),
          ),
      ],
    );
  }

  Widget _chroma(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<ChromaMode>(
          initialValue: s.chroma,
          decoration: InputDecoration(labelText: l10n.jpegChroma),
          items: [
            for (final c in ChromaMode.values)
              DropdownMenuItem(value: c, child: Text(c.label)),
          ],
          onChanged: (v) {
            if (v != null) s.setChroma(v);
          },
        ),
      ],
    );
  }

  Widget _metadataToggle(
    BuildContext context, {
    required bool value,
    required ValueChanged<bool> onChanged,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: value,
        onChanged: onChanged,
        title: Text(label, style: const TextStyle(fontSize: 12.5)),
      ),
    );
  }

  Widget _metadata(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: s.stripMetadata,
          onChanged: s.setStripMetadata,
          title: Text(l10n.stripMetadata, style: TextStyle(fontSize: 13.5)),
          subtitle: Text(
            s.stripMetadata ? l10n.stripMetadataHint : l10n.stripMetadataOff,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (s.stripMetadata) ...[
          _metadataToggle(
            context,
            value: s.stripGps,
            onChanged: s.setStripGps,
            label: l10n.stripLocation,
          ),
          _metadataToggle(
            context,
            value: s.stripCamera,
            onChanged: s.setStripCamera,
            label: 'Camera make, model and settings',
          ),
          _metadataToggle(
            context,
            value: s.stripTimestamps,
            onChanged: s.setStripTimestamps,
            label: l10n.stripDates,
          ),
          _metadataToggle(
            context,
            value: s.stripThumbnail,
            onChanged: s.setStripThumbnail,
            label: l10n.stripThumbnail,
          ),
        ],
        if (s.format == OutputFormat.keep)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.keepExtensionWhenKeepFormat,
            onChanged: s.setKeepExtensionWhenKeepFormat,
            title: Text(l10n.keepExtension, style: TextStyle(fontSize: 13.5)),
          ),
      ],
    );
  }

  // ------------------------------------------------------------- transform
  Widget _transform(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => s.rotateBy(1),
            icon: const Icon(Icons.rotate_90_degrees_cw_outlined, size: 17),
            label: Text(
              s.rotateQuarterTurns == 0
                  ? l10n.rotate
                  : '${s.rotateQuarterTurns * 90}°',
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => s.setFlipH(!s.flipH),
            icon: const Icon(Icons.flip, size: 17),
            label: Text(s.flipH ? l10n.unflipH : l10n.flipH),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => s.setFlipV(!s.flipV),
            icon: const Icon(Icons.flip_camera_android_outlined, size: 17),
            label: Text(s.flipV ? l10n.unflipV : l10n.flipV),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ adjustments
  Widget _adjustments(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    final a = s.adjustments;
    void set(Adjustments next) => s.setAdjustments(next);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.autoLevels,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: s.resetAdjustments,
              child: Text(AppLocalizations.of(context).reset),
            ),
          ],
        ),
        _Slider(
          label: l10n.brightness,
          value: a.brightness.toDouble(),
          min: -100,
          max: 100,
          display: a.brightness.toStringAsFixed(0),
          onChanged: (v) => set(a.copyWith(brightness: v)),
        ),
        _Slider(
          label: l10n.contrast,
          value: a.contrast.toDouble(),
          min: -100,
          max: 100,
          display: a.contrast.toStringAsFixed(0),
          onChanged: (v) => set(a.copyWith(contrast: v)),
        ),
        _Slider(
          label: l10n.saturation,
          value: a.saturation.toDouble(),
          min: -100,
          max: 100,
          display: a.saturation.toStringAsFixed(0),
          onChanged: (v) => set(a.copyWith(saturation: v)),
        ),
        _Slider(
          label: l10n.exposure,
          value: a.exposure.toDouble(),
          min: -100,
          max: 100,
          display: a.exposure.toStringAsFixed(0),
          onChanged: (v) => set(a.copyWith(exposure: v)),
        ),
        _Slider(
          label: l10n.hue,
          value: a.hue.toDouble(),
          min: -180,
          max: 180,
          display: a.hue.toStringAsFixed(0),
          onChanged: (v) => set(a.copyWith(hue: v)),
        ),
        _Slider(
          label: l10n.gamma,
          value: a.gamma.toDouble(),
          min: 10,
          max: 300,
          display: a.gamma.toStringAsFixed(0),
          onChanged: (v) => set(a.copyWith(gamma: v)),
        ),
        _Slider(
          label: l10n.amount,
          value: a.amount.toDouble(),
          min: 0,
          max: 100,
          display: '${(a.amount * 100).round()}%',
          onChanged: (v) => set(a.copyWith(amount: v / 100)),
        ),
      ],
    );
  }

  Widget _filters(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        _Slider(
          label: l10n.grayscale,
          value: s.grayscale,
          min: 0,
          max: 1,
          display: '${(s.grayscale * 100).round()}%',
          onChanged: s.setGrayscale,
        ),
        _Slider(
          label: l10n.sepia,
          value: s.sepia,
          min: 0,
          max: 1,
          display: '${(s.sepia * 100).round()}%',
          onChanged: s.setSepia,
        ),
        _Slider(
          label: l10n.blurRadius,
          value: s.blurRadius,
          min: 0,
          max: 40,
          display: s.blurRadius.toStringAsFixed(1),
          onChanged: s.setBlurRadius,
        ),
        _Slider(
          label: l10n.sharpen,
          value: s.sharpenAmount,
          min: 0,
          max: 2,
          display: s.sharpenAmount.toStringAsFixed(2),
          onChanged: s.setSharpenAmount,
        ),
      ],
    );
  }

  // -------------------------------------------------------------- watermark
  Widget _watermark(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    final w = s.watermark;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SyncedTextField(
                value: w.text,
                hint: '© yourname',
                label: l10n.watermarkText,
                icon: Icons.text_fields,
                onChanged: (v) => s.setWatermark(
                  w.copyWith(text: v, enabled: v.trim().isNotEmpty),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Switch(
              value: w.active,
              onChanged: (v) => s.setWatermark(w.copyWith(enabled: v)),
            ),
          ],
        ),
        if (w.active) ...[
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<WatermarkCorner>(
            initialValue: w.corner,
            decoration: InputDecoration(labelText: l10n.position),
            items: [
              DropdownMenuItem(
                value: WatermarkCorner.topLeft,
                child: Text(l10n.topLeft),
              ),
              DropdownMenuItem(
                value: WatermarkCorner.topRight,
                child: Text(l10n.topRight),
              ),
              DropdownMenuItem(
                value: WatermarkCorner.center,
                child: Text(l10n.center),
              ),
              DropdownMenuItem(
                value: WatermarkCorner.bottomLeft,
                child: Text(l10n.bottomLeft),
              ),
              DropdownMenuItem(
                value: WatermarkCorner.bottomRight,
                child: Text(l10n.bottomRight),
              ),
            ],
            onChanged: (v) {
              if (v != null) s.setWatermark(w.copyWith(corner: v));
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _Slider(
            label: l10n.watermarkSize,
            value: w.scale,
            min: 0.01,
            max: 0.25,
            display: '${(w.scale * 100).round()}%',
            onChanged: (v) => s.setWatermark(w.copyWith(scale: v)),
          ),
          _Slider(
            label: l10n.opacity,
            value: w.opacity,
            min: 0,
            max: 1,
            display: '${(w.opacity * 100).round()}%',
            onChanged: (v) => s.setWatermark(w.copyWith(opacity: v)),
          ),
          _Slider(
            label: l10n.margin,
            value: w.margin,
            min: 0,
            max: 0.2,
            display: '${(w.margin * 100).round()}%',
            onChanged: (v) => s.setWatermark(w.copyWith(margin: v)),
          ),
        ],
      ],
    );
  }

  // ----------------------------------------------------------------- output
  Widget _naming(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SyncedTextField(
          value: s.nameTemplate,
          hint: '{name}',
          label: l10n.filenameTemplate,
          icon: Icons.tag,
          onChanged: s.setNameTemplate,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final t in s.templateTokens)
              ActionChip(
                label: Text(t, style: const TextStyle(fontSize: 10.5)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: () => s.setNameTemplate('${s.nameTemplate}$t'),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: s.overwrite,
          onChanged: s.setOverwrite,
          title: Text(l10n.overwrite, style: TextStyle(fontSize: 13.5)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: s.writeImmediately,
          onChanged: s.setWriteImmediately,
          title: Text(l10n.writeImmediately, style: TextStyle(fontSize: 13.5)),
          subtitle: Text(
            'Frees memory during large batches; re-running needs the files re-added',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _Slider(
          label: l10n.memoryBudget,
          value: s.memoryBudgetMb.toDouble(),
          min: 64,
          max: 2048,
          display: '${s.memoryBudgetMb} MB',
          onChanged: (v) => s.setMemoryBudgetMb(v.round()),
        ),
      ],
    );
  }

  Widget _destination(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                s.outputDirectory.isEmpty
                    ? l10n.savesToCurrentFolder
                    : s.outputDirectory,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (controller.canPickDirectory)
              TextButton.icon(
                onPressed: controller.chooseOutputDirectory,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: Text(AppLocalizations.of(context).browse),
              ),
          ],
        ),
      ],
    );
  }

  Widget _extraOutputs(BuildContext context, ResizeSettings s) {
    final l10n = AppLocalizations.of(context);
    final extras = s.extraOutputs;
    final available = Presets.all
        .where((p) => !extras.any((e) => e.name == p.name))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Each file is exported once per output below, plus the main '
          'settings above, from a single decode.',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final e in extras)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text(e.name, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                [
                  if (e.width != null && e.height != null)
                    '${e.width}x${e.height}',
                  if (e.format != null) e.format!.toUpperCase(),
                  if (e.targetKb != null) '≤${e.targetKb} KB',
                ].join('  ·  '),
                style: const TextStyle(fontSize: 11),
              ),
              trailing: IconButton(
                tooltip: 'Remove ${e.name}',
                icon: const Icon(Icons.close, size: 17),
                onPressed: () => s.removeExtraOutput(e.name),
              ),
            ),
          ),
        if (available.isNotEmpty)
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.addOutput,
              prefixIcon: const Icon(Icons.add, size: 19),
            ),
            items: [
              for (final p in available)
                DropdownMenuItem(value: p.name, child: Text(p.name)),
            ],
            onChanged: (v) {
              if (v == null) return;
              final p = Presets.byName(v);
              if (p != null) s.addExtraOutput(p);
            },
          )
        else
          Text(
            extras.isEmpty ? l10n.extraOutputsEmpty : l10n.extraOutputsFull,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        if (extras.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: s.clearExtraOutputs,
              child: Text(AppLocalizations.of(context).clearAll),
            ),
          ),
      ],
    );
  }
}

class _SyncedTextField extends StatefulWidget {
  const _SyncedTextField({
    required this.value,
    required this.onChanged,
    required this.label,
    required this.icon,
    this.hint,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;
  final IconData icon;
  final String? hint;

  @override
  State<_SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<_SyncedTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(_SyncedTextField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value &&
        !_focus.hasFocus &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      style: const TextStyle(fontSize: 12.5),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: Icon(widget.icon, size: 18),
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _PadColorRow extends StatelessWidget {
  const _PadColorRow({required this.settings});

  final ResizeSettings settings;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          l10n.padColour,
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Wrap(
            spacing: 6,
            children: [
              for (final c in const [
                Color(0xFFFFFFFF),
                Color(0xFF000000),
                Color(0xFFB0BEC5),
                Color(0xFF90CAF9),
              ])
                GestureDetector(
                  onTap: () => s.setPadColor(c),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c.toARGB32() == s.padColor.toARGB32()
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: c.toARGB32() == s.padColor.toARGB32() ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: enabled
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.disabledColor,
                fontSize: 11.5,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: enabled
                    ? theme.colorScheme.primary
                    : theme.disabledColor,
                inactiveTrackColor: theme.colorScheme.surfaceContainerHighest,
                thumbColor: enabled
                    ? theme.colorScheme.primary
                    : theme.disabledColor,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              display,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontSize: 11.5,
                color: enabled
                    ? theme.colorScheme.onSurface
                    : theme.disabledColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.allowZeroAsNull = false,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final String? hint;
  final bool allowZeroAsNull;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value == 0 && widget.allowZeroAsNull
        ? ''
        : widget.value.toString(),
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focus.hasFocus) {
      final next = widget.value == 0 && widget.allowZeroAsNull
          ? ''
          : widget.value.toString();
      if (_controller.text != next) _controller.text = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) {
      if (widget.allowZeroAsNull) widget.onChanged(0);
      return;
    }
    final v = int.tryParse(cleaned);
    if (v != null) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: _commit,
      onTapOutside: (_) {
        _focus.unfocus();
        _commit(_controller.text);
      },
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
      ),
    );
  }
}
