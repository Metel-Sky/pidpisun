import 'dart:io';

import 'package:flutter/material.dart';

import 'services/portable_store.dart';
import 'strings.dart';

/// Typical ink colors for monochrome PNG stamps and signatures.
/// `null` keeps the original pixels; a value tints opaque pixels via [BlendMode.srcIn].
abstract final class StampInk {
  static const swatches = <int>[
    0xFF1B365D,
    0xFF1565C0,
    0xFF0D47A1,
    0xFFC62828,
    0xFFAD1457,
    0xFF2E7D32,
    0xFF111111,
    0xFF5D4037,
    0xFF6A1B9A,
    0xFF00695C,
  ];

  static String? hex(int? argb) {
    if (argb == null) {
      return null;
    }
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    String part(int value) => value.toRadixString(16).padLeft(2, '0');
    return '#${part(r)}${part(g)}${part(b)}'.toUpperCase();
  }

  static ColorFilter? filterFor(int? argb) {
    if (argb == null) {
      return null;
    }
    return ColorFilter.mode(Color(argb), BlendMode.srcIn);
  }
}

class StampImage extends StatelessWidget {
  const StampImage({
    super.key,
    required this.path,
    this.color,
    this.fit = BoxFit.fill,
    this.filterQuality = FilterQuality.high,
  });

  final String path;
  final int? color;
  final BoxFit fit;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final bytes = PortableStore.readPngBytes(path);
    final image = bytes != null
        ? Image.memory(
            bytes,
            fit: fit,
            filterQuality: filterQuality,
            gaplessPlayback: true,
          )
        : Image.file(
            File(path),
            fit: fit,
            filterQuality: filterQuality,
          );
    final filter = StampInk.filterFor(color);
    if (filter == null) {
      return image;
    }
    return ColorFiltered(colorFilter: filter, child: image);
  }
}

class StampColorPalette extends StatelessWidget {
  const StampColorPalette({
    super.key,
    required this.selected,
    required this.onChanged,
    this.swatchSize = 22,
  });

  final int? selected;
  final ValueChanged<int?> onChanged;
  final double swatchSize;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Swatch(
          size: swatchSize,
          selected: selected == null,
          tooltip: S.originalColor,
          onTap: () => onChanged(null),
          child: CustomPaint(
            painter: const _OriginalSwatchPainter(),
            size: Size.square(swatchSize - 6),
          ),
        ),
        for (final value in StampInk.swatches)
          _Swatch(
            size: swatchSize,
            selected: selected == value,
            tooltip: StampInk.hex(value) ?? '',
            onTap: () => onChanged(value),
            color: Color(value),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.size,
    required this.selected,
    required this.tooltip,
    required this.onTap,
    this.color,
    this.child,
  });

  final double size;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outlineVariant;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: border, width: selected ? 2.5 : 1),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: border.withValues(alpha: 0.35),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
            child: child == null
                ? null
                : Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _OriginalSwatchPainter extends CustomPainter {
  const _OriginalSwatchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const colors = [
      Color(0xFFC62828),
      Color(0xFF1565C0),
      Color(0xFF2E7D32),
      Color(0xFFF9A825),
    ];
    final rect = Offset.zero & size;
    final paint = Paint()..style = PaintingStyle.fill;
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    final halfW = size.width / 2;
    final halfH = size.height / 2;
    paint.color = colors[0];
    canvas.drawRect(Rect.fromLTWH(0, 0, halfW, halfH), paint);
    paint.color = colors[1];
    canvas.drawRect(Rect.fromLTWH(halfW, 0, halfW, halfH), paint);
    paint.color = colors[2];
    canvas.drawRect(Rect.fromLTWH(0, halfH, halfW, halfH), paint);
    paint.color = colors[3];
    canvas.drawRect(Rect.fromLTWH(halfW, halfH, halfW, halfH), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
