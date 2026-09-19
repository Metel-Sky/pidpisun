import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:podpisun/models/models.dart';
import 'package:podpisun/stamp_ink.dart';
import 'package:podpisun/strings.dart';

void main() {
  test('toEngineJson додає колір лише коли він заданий', () {
    const plain = StampPlacement(
      id: 'a',
      pageIndex: 0,
      x: 1,
      y: 2,
      width: 10,
      height: 8,
      pngPath: '/tmp/stamp.png',
      aspectRatio: 1.25,
    );
    expect(plain.toEngineJson().containsKey('color'), isFalse);

    final tinted = plain.copyWith(color: 0xFFC62828);
    expect(tinted.toEngineJson()['color'], '#C62828');

    final restored = tinted.copyWith(clearColor: true);
    expect(restored.color, isNull);
    expect(restored.toEngineJson().containsKey('color'), isFalse);
  });

  test('поворот на PDF не змінює розмір рамки', () {
    const stamp = StampPlacement(
      id: 'a',
      pageIndex: 0,
      x: 10,
      y: 20,
      width: 40,
      height: 20,
      pngPath: '/tmp/stamp.png',
      aspectRatio: 2,
    );
    final turned = stamp.copyWith(rotation: 37.5);
    expect(turned.rotation, 37.5);
    expect(turned.width, 40);
    expect(turned.height, 20);
    expect(turned.toEngineJson()['rotate'], 37.5);
    expect(
      StampPlacement.normalizeRotation(-45),
      315,
    );
  });

  test('міліметри й точки PDF пропорційні', () {
    expect(StampPlacement.parseMm('40,5'), 40.5);
    expect(StampPlacement.formatMm(40.0), '40');
    const widthMm = 40.0;
    final points = StampPlacement.mmToPoints(widthMm);
    expect(StampPlacement.pointsToMm(points), closeTo(widthMm, 0.001));
    final height = points / 2;
    expect(
      StampPlacement.pointsToMm(height),
      closeTo(widthMm / 2, 0.001),
    );
  });

  testWidgets('палітра показує оригінал і чорнильні кольори', (tester) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StampColorPalette(
            selected: selected,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.byType(StampColorPalette), findsOneWidget);
    expect(find.byTooltip(S.originalColor), findsOneWidget);

    await tester.tap(find.byTooltip('#C62828'));
    expect(selected, 0xFFC62828);
  });
}
