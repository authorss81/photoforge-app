import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

import '../../core/engine.dart';

/// Lazily generated, once-per-mount preview thumbnail.
class ImageThumb extends StatefulWidget {
  const ImageThumb({
    super.key,
    required this.bytes,
    this.maxDim = 128,
    this.fit = BoxFit.cover,
    this.borderRadius = 8,
  });

  final Uint8List bytes;
  final int maxDim;
  final BoxFit fit;
  final double borderRadius;

  @override
  State<ImageThumb> createState() => _ImageThumbState();
}

class _ImageThumbState extends State<ImageThumb> {
  Future<Uint8List?>? _future;
  String? _token;

  @override
  void didUpdateWidget(ImageThumb old) {
    super.didUpdateWidget(old);
    if (!identical(old.bytes, widget.bytes)) _start();
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    final token = '${widget.bytes.length}:${widget.maxDim}';
    if (_token == token && _future != null) return;
    _token = token;
    _future = computeThumb(widget.bytes, widget.maxDim);
  }

  static Future<Uint8List?> computeThumb(Uint8List b, int dim) async {
    return ResizeEngine.thumbnail(b, maxDim: dim);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: FutureBuilder<Uint8List?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox.expand(
                child: Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  ),
                ),
              );
            }
            final data = snap.data;
            if (data == null || data.isEmpty) {
              return const SizedBox.expand(
                child: Icon(Icons.broken_image_outlined, size: 18),
              );
            }
            return Image.memory(data, fit: widget.fit, gaplessPlayback: true);
          },
        ),
      ),
    );
  }
}

/// A big before/after preview with a draggable divider.
///
/// Both images are laid out identically (BoxFit.contain, centred), so they
/// overlap exactly and the divider reveals one side or the other. Dragging
/// starts only on the handle, never on the image, so pinch-zoom and pan keep
/// working everywhere else. Keyboard users get arrow keys on the focused
/// handle, and screen readers get the Before/Split/After toggle upstream,
///
/// which jumps to a full view without needing the drag at all.
class LargePreview extends StatefulWidget {
  const LargePreview({
    super.key,
    required this.before,
    required this.after,
    this.label,
    this.icon = Icons.image_outlined,
    this.split = true,
  });

  final Uint8List? before;
  final Uint8List? after;
  final String? label;
  final IconData icon;

  /// False forces a single full view of [after] (or [before] when after is
  /// missing). Used by the accessible toggle.
  final bool split;

  @override
  State<LargePreview> createState() => _LargePreviewState();
}

class _LargePreviewState extends State<LargePreview> {
  double _fraction = 0.5;
  final FocusNode _handleFocus = FocusNode();

  @override
  void dispose() {
    _handleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final before = widget.before;
    final after = widget.after ?? before;
    final showSplit = widget.split && before != null && widget.after != null;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (after == null || after.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.icon,
                    size: 40,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Nothing to preview',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else if (!showSplit)
            InteractiveViewer(
              maxScale: 12,
              child: Image.memory(after, fit: BoxFit.contain),
            )
          else
            _SplitView(
              before: before,
              after: after,
              fraction: _fraction,
              onFraction: (v) => setState(() => _fraction = v),
              handleFocus: _handleFocus,
            ),
          if (widget.label != null)
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.scrim.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  widget.label!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SplitView extends StatelessWidget {
  const _SplitView({
    required this.before,
    required this.after,
    required this.fraction,
    required this.onFraction,
    required this.handleFocus,
  });

  final Uint8List before;
  final Uint8List after;
  final double fraction;
  final ValueChanged<double> onFraction;
  final FocusNode handleFocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final dx = (fraction.clamp(0.02, 0.98)) * constraints.maxWidth;
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(after, fit: BoxFit.contain),
            ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: fraction.clamp(0.02, 0.98),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: Image.memory(before, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              left: dx - 22,
              top: 0,
              bottom: 0,
              width: 44,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (d) {
                  onFraction(
                    ((dx + d.delta.dx) / constraints.maxWidth).clamp(
                      0.02,
                      0.98,
                    ),
                  );
                },
                child: Semantics(
                  label: 'Comparison divider',
                  hint: 'Drag to compare, or use arrow keys',
                  child: Focus(
                    focusNode: handleFocus,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        const step = 0.05;
                        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                          onFraction((fraction - step).clamp(0.02, 0.98));
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                          onFraction((fraction + step).clamp(0.02, 0.98));
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Container(
                      color: Colors.transparent,
                      child: Center(
                        child: Container(
                          width: 3,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.scrim.withValues(
                                  alpha: 0.4,
                                ),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.primary,
                              ),
                              child: Icon(
                                Icons.compare_arrows_rounded,
                                size: 15,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
