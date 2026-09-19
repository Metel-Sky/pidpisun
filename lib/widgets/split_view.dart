import 'package:flutter/material.dart';

class ThreePaneSplit extends StatefulWidget {
  const ThreePaneSplit({
    super.key,
    required this.left,
    required this.middle,
    required this.right,
  });

  final Widget left;
  final Widget middle;
  final Widget right;

  @override
  State<ThreePaneSplit> createState() => _ThreePaneSplitState();
}

class _ThreePaneSplitState extends State<ThreePaneSplit> {
  static const _minLeft = 200.0;
  static const _minMiddle = 180.0;
  static const _minRight = 320.0;
  static const _handle = 6.0;

  double _leftWidth = 280;
  double _middleWidth = 240;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        _clampWidths(maxWidth);
        return Row(
          children: [
            SizedBox(width: _leftWidth, child: widget.left),
            _SplitHandle(
              onDrag: (delta) {
                setState(() {
                  _leftWidth += delta;
                  _clampWidths(maxWidth);
                });
              },
            ),
            SizedBox(width: _middleWidth, child: widget.middle),
            _SplitHandle(
              onDrag: (delta) {
                setState(() {
                  _middleWidth += delta;
                  _clampWidths(maxWidth);
                });
              },
            ),
            Expanded(child: widget.right),
          ],
        );
      },
    );
  }

  void _clampWidths(double maxWidth) {
    final available = maxWidth - _handle * 2;
    var left = _leftWidth.clamp(_minLeft, available - _minMiddle - _minRight);
    var middle = _middleWidth.clamp(_minMiddle, available - left - _minRight);
    final right = available - left - middle;
    if (right < _minRight) {
      middle = (available - left - _minRight).clamp(_minMiddle, available);
      left = (available - middle - _minRight).clamp(_minLeft, available);
    }
    _leftWidth = left.toDouble();
    _middleWidth = middle.toDouble();
  }
}

class _SplitHandle extends StatelessWidget {
  const _SplitHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: SizedBox(
          width: 6,
          child: Center(child: Container(width: 1, color: color)),
        ),
      ),
    );
  }
}
