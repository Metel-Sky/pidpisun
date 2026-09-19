import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/models.dart';
import '../providers/workspace_providers.dart';
import '../services/file_browser_service.dart';
import '../stamp_ink.dart';
import '../strings.dart';

class StampPageOverlay extends ConsumerWidget {
  const StampPageOverlay({super.key, required this.page});

  final PdfPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(documentSessionProvider);
    final dragging = ref.watch(draggingStampPathProvider);
    final pageIndex = page.pageNumber - 1;
    final stamps =
        session?.stamps
            .where((stamp) => stamp.pageIndex == pageIndex)
            .toList() ??
        const [];

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaleX = constraints.maxWidth / page.width;
        final scaleY = constraints.maxHeight / page.height;
        return DragTarget<String>(
          hitTestBehavior: dragging == null
              ? HitTestBehavior.deferToChild
              : HitTestBehavior.opaque,
          onWillAcceptWithDetails: (details) =>
              FileBrowserService.isPng(details.data),
          onAcceptWithDetails: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) {
              return;
            }
            final local = box.globalToLocal(details.offset);
            ref
                .read(documentSessionProvider.notifier)
                .addStamp(
                  pngPath: details.data,
                  pageIndex: pageIndex,
                  x: local.dx / scaleX,
                  y: local.dy / scaleY,
                  pageWidth: page.width,
                  pageHeight: page.height,
                );
          },
          builder: (context, candidate, rejected) {
            final highlighted = candidate.isNotEmpty;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                if (dragging != null || highlighted)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: highlighted
                            ? Colors.blue.withValues(alpha: 0.10)
                            : Colors.transparent,
                      ),
                    ),
                  ),
                for (final stamp in stamps)
                  StampWidget(
                    stamp: stamp,
                    scaleX: scaleX,
                    scaleY: scaleY,
                    pageWidth: page.width,
                    pageHeight: page.height,
                    selected: stamp.id == session?.selectedStampId,
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

enum _ResizeHandle { n, s, e, w, ne, nw, se, sw }

class StampWidget extends ConsumerWidget {
  const StampWidget({
    super.key,
    required this.stamp,
    required this.scaleX,
    required this.scaleY,
    required this.pageWidth,
    required this.pageHeight,
    required this.selected,
  });

  final StampPlacement stamp;
  final double scaleX;
  final double scaleY;
  final double pageWidth;
  final double pageHeight;
  final bool selected;

  static const _handleSize = 12.0;
  static const _rotateHandleSize = 20.0;
  static const _rotateReach = 28.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boxW = stamp.width * scaleX;
    final boxH = stamp.height * scaleY;
    final center = Offset(boxW / 2, boxH / 2);
    final radians = stamp.rotation * math.pi / 180;
    final reach = boxH / 2 + _rotateReach;
    final pad = selected
        ? reach + _rotateHandleSize / 2 + 4
        : _handleSize / 2;
    final handleCenter = Offset(
      center.dx + reach * math.sin(radians),
      center.dy - reach * math.cos(radians),
    );

    return Positioned(
      left: stamp.x * scaleX - pad,
      top: stamp.y * scaleY - pad,
      width: boxW + pad * 2,
      height: boxH + pad * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: pad,
            top: pad,
            width: boxW,
            height: boxH,
            child: Transform.rotate(
              angle: radians,
              child: _EagerPan(
                cursor: SystemMouseCursors.grab,
                onTap: () {
                  Focus.maybeOf(context)?.requestFocus();
                  ref
                      .read(documentSessionProvider.notifier)
                      .selectStamp(stamp.id);
                },
                onPanStart: () {
                  Focus.maybeOf(context)?.requestFocus();
                  ref
                      .read(documentSessionProvider.notifier)
                      .selectStamp(stamp.id);
                },
                onPanUpdate: (details) {
                  final next = stamp.copyWith(
                    x: (stamp.x + details.delta.dx / scaleX).clamp(
                      0,
                      (pageWidth - stamp.width).clamp(0, pageWidth),
                    ),
                    y: (stamp.y + details.delta.dy / scaleY).clamp(
                      0,
                      (pageHeight - stamp.height).clamp(0, pageHeight),
                    ),
                  );
                  ref.read(documentSessionProvider.notifier).updateStamp(next);
                },
                onSecondaryTapDown: (details) => _showDeleteMenu(
                  context,
                  ref,
                  details.globalPosition,
                ),
                child: Opacity(
                  opacity: stamp.opacity.clamp(0.15, 1.0),
                  child: StampImage(
                    path: stamp.pngPath,
                    color: stamp.color,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
          if (selected) ...[
            Positioned(
              left: pad,
              top: pad,
              width: boxW,
              height: boxH,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RotateGuidePainter(
                    from: center,
                    to: handleCenter,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            Positioned(
              left: pad + handleCenter.dx - _rotateHandleSize / 2,
              top: pad + handleCenter.dy - _rotateHandleSize / 2,
              child: _EagerPan(
                cursor: SystemMouseCursors.grab,
                onPanStart: () {
                  ref
                      .read(documentSessionProvider.notifier)
                      .selectStamp(stamp.id);
                },
                onPanUpdate: (details) {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null) {
                    return;
                  }
                  final local = box.globalToLocal(details.globalPosition);
                  final vector = local - Offset(pad, pad) - center;
                  final degrees =
                      math.atan2(vector.dx, -vector.dy) * 180 / math.pi;
                  ref
                      .read(documentSessionProvider.notifier)
                      .setSelectedRotation(degrees);
                },
                child: Tooltip(
                  message: S.rotateStamp,
                  child: Container(
                    width: _rotateHandleSize,
                    height: _rotateHandleSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.rotate_right,
                      size: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
            for (final handle in _ResizeHandle.values)
              Positioned(
                left:
                    pad +
                    (boxW / 2) * (_alignment(handle).x + 1) -
                    _handleSize / 2,
                top:
                    pad +
                    (boxH / 2) * (_alignment(handle).y + 1) -
                    _handleSize / 2,
                child: _buildHandle(context, ref, handle),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _showDeleteMenu(
    BuildContext context,
    WidgetRef ref,
    Offset globalPosition,
  ) async {
    ref.read(documentSessionProvider.notifier).selectStamp(stamp.id);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(value: 'delete', child: Text(S.deleteStamp)),
      ],
    );
    if (action == 'delete') {
      ref.read(documentSessionProvider.notifier).removeStamp(stamp.id);
    }
  }

  Widget _buildHandle(
    BuildContext context,
    WidgetRef ref,
    _ResizeHandle handle,
  ) {
    final color = Theme.of(context).colorScheme.primary;
    return MouseRegion(
      cursor: _cursorFor(handle),
      child: _EagerPan(
        cursor: _cursorFor(handle),
        onPanStart: () {
          ref.read(documentSessionProvider.notifier).selectStamp(stamp.id);
        },
        onPanUpdate: (details) {
          final next = _resized(
            dx: details.delta.dx / scaleX,
            dy: details.delta.dy / scaleY,
            handle: handle,
          );
          ref.read(documentSessionProvider.notifier).updateStamp(next);
        },
        child: Container(
          width: _handleSize,
          height: _handleSize,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Alignment _alignment(_ResizeHandle handle) {
    return switch (handle) {
      _ResizeHandle.n => Alignment.topCenter,
      _ResizeHandle.s => Alignment.bottomCenter,
      _ResizeHandle.e => Alignment.centerRight,
      _ResizeHandle.w => Alignment.centerLeft,
      _ResizeHandle.ne => Alignment.topRight,
      _ResizeHandle.nw => Alignment.topLeft,
      _ResizeHandle.se => Alignment.bottomRight,
      _ResizeHandle.sw => Alignment.bottomLeft,
    };
  }

  MouseCursor _cursorFor(_ResizeHandle handle) {
    return switch (handle) {
      _ResizeHandle.n => SystemMouseCursors.resizeUp,
      _ResizeHandle.s => SystemMouseCursors.resizeDown,
      _ResizeHandle.e => SystemMouseCursors.resizeRight,
      _ResizeHandle.w => SystemMouseCursors.resizeLeft,
      _ResizeHandle.ne => SystemMouseCursors.resizeUpRight,
      _ResizeHandle.nw => SystemMouseCursors.resizeUpLeft,
      _ResizeHandle.se => SystemMouseCursors.resizeDownRight,
      _ResizeHandle.sw => SystemMouseCursors.resizeDownLeft,
    };
  }

  StampPlacement _resized({
    required double dx,
    required double dy,
    required _ResizeHandle handle,
  }) {
    const minSize = 24.0;
    var x = stamp.x;
    var y = stamp.y;
    var width = stamp.width;
    var height = stamp.height;
    final aspect = stamp.aspectRatio <= 0 ? 1.0 : stamp.aspectRatio;
    final right = stamp.x + stamp.width;
    final bottom = stamp.y + stamp.height;

    final fromLeft =
        handle == _ResizeHandle.w ||
        handle == _ResizeHandle.nw ||
        handle == _ResizeHandle.sw;
    final fromRight =
        handle == _ResizeHandle.e ||
        handle == _ResizeHandle.ne ||
        handle == _ResizeHandle.se;
    final fromTop =
        handle == _ResizeHandle.n ||
        handle == _ResizeHandle.nw ||
        handle == _ResizeHandle.ne;
    final fromBottom =
        handle == _ResizeHandle.s ||
        handle == _ResizeHandle.sw ||
        handle == _ResizeHandle.se;

    if (fromLeft || fromRight) {
      if (fromRight) {
        width = (width + dx).clamp(minSize, pageWidth - x);
      } else {
        width = (width - dx).clamp(minSize, right);
        x = right - width;
      }
      height = width / aspect;
      if (fromTop) {
        y = bottom - height;
      } else if (!fromBottom) {
        y = stamp.y + (stamp.height - height) / 2;
      }
    } else if (fromTop || fromBottom) {
      if (fromBottom) {
        height = (height + dy).clamp(minSize, pageHeight - y);
      } else {
        height = (height - dy).clamp(minSize, bottom);
        y = bottom - height;
      }
      width = height * aspect;
      if (fromLeft) {
        x = right - width;
      } else if (!fromRight) {
        x = stamp.x + (stamp.width - width) / 2;
      }
    }

    if (x < 0) {
      width += x;
      x = 0;
      height = width / aspect;
    }
    if (y < 0) {
      height += y;
      y = 0;
      width = height * aspect;
    }
    if (x + width > pageWidth) {
      width = math.max(minSize, pageWidth - x);
      height = width / aspect;
    }
    if (y + height > pageHeight) {
      height = math.max(minSize, pageHeight - y);
      width = height * aspect;
    }

    return stamp.copyWith(
      x: x.clamp(0, pageWidth),
      y: y.clamp(0, pageHeight),
      width: width.clamp(minSize, pageWidth),
      height: height.clamp(minSize, pageHeight),
    );
  }
}

class _EagerPan extends StatelessWidget {
  const _EagerPan({
    required this.child,
    this.onPanStart,
    this.onPanUpdate,
    this.onTap,
    this.onSecondaryTapDown,
    this.cursor,
  });

  final Widget child;
  final VoidCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final MouseCursor? cursor;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _EagerPanRecognizer: GestureRecognizerFactoryWithHandlers<_EagerPanRecognizer>(
          _EagerPanRecognizer.new,
          (instance) {
            instance.onStart = onPanStart == null && onPanUpdate == null
                ? null
                : (details) => onPanStart?.call();
            instance.onUpdate = onPanUpdate;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onSecondaryTapDown: onSecondaryTapDown,
        child: MouseRegion(
          cursor: cursor ?? MouseCursor.defer,
          child: child,
        ),
      ),
    );
  }
}

class _EagerPanRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _RotateGuidePainter extends CustomPainter {
  const _RotateGuidePainter({
    required this.from,
    required this.to,
    required this.color,
  });

  final Offset from;
  final Offset to;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.25
      ..style = PaintingStyle.stroke;
    canvas.drawLine(from, to, paint);
  }

  @override
  bool shouldRepaint(covariant _RotateGuidePainter oldDelegate) {
    return oldDelegate.from != from ||
        oldDelegate.to != to ||
        oldDelegate.color != color;
  }
}
