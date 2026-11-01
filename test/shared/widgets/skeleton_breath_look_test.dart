// 骨架呼吸的長相（ADR 0024）：呼吸時每個佔位形狀在螢幕橫向位置 u 的深淺，
// 是佔位色的透明度乘上 `Skeleton.breathAt(相位, u)`；實色的形狀（卡片底）
// 不呼吸。不管骨架怎麼畫（逐個形狀畫漸層，或整塊畫好再蓋一層遮罩），畫出來
// 都要和照這個定義一行一行像素畫的一樣，每個像素最多差 [_tolerance] 階。
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

const _size = Size(400, 200);
const _tolerance = 2;
const _radius = BorderRadius.all(Radius.circular(4));
const _cardRadius = BorderRadius.all(Radius.circular(12));

/// 一個形狀在畫面上的位置；[fill] 給了是不呼吸的實色。
typedef _Shape = ({Rect rect, BorderRadius radius, Color? fill});

/// 一條滿版的、一排三個，和一塊卡片底上的三條（[SkeletonShapes]）。
List<_Shape> _shapes(Color card) => [
  (rect: const Rect.fromLTWH(0, 0, 400, 20), radius: _radius, fill: null),
  for (final x in [10.0, 140.0, 270.0])
    (rect: Rect.fromLTWH(x, 30, 120, 20), radius: _radius, fill: null),
  (rect: const Rect.fromLTWH(10, 60, 380, 90), radius: _cardRadius, fill: card),
  for (final bar in const [
    Rect.fromLTWH(20, 70, 200, 14),
    Rect.fromLTWH(20, 100, 300, 14),
    Rect.fromLTWH(250, 70, 120, 14),
  ])
    (rect: bar, radius: _radius, fill: null),
];

Widget _skeleton(Color card) {
  final shapes = _shapes(card);
  return Skeleton(
    child: Stack(
      children: [
        for (final shape in shapes.take(4))
          Positioned.fromRect(
            rect: shape.rect,
            child: SkeletonBox(borderRadius: shape.radius),
          ),
        Positioned(
          left: 0,
          top: 60,
          width: 400,
          height: 90,
          child: SkeletonShapes(
            height: 90,
            shapes: (_) => [
              for (final shape in shapes.skip(4))
                SkeletonShape(
                  shape.rect.shift(const Offset(0, -60)),
                  radius: shape.radius,
                  fill: shape.fill,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 照定義畫：每個呼吸的形狀一行一行像素，各用自己那一行的深淺。
class _Reference extends CustomPainter {
  _Reference(this.shapes, this.color, this.phase) : super(repaint: phase);

  final List<_Shape> shapes;
  final Color color;
  final ValueListenable<double> phase;

  @override
  void paint(Canvas canvas, Size size) {
    for (final shape in shapes) {
      final rrect = shape.radius.toRRect(shape.rect);
      final fill = shape.fill;
      if (fill != null) {
        canvas.drawRRect(rrect, Paint()..color = fill);
        continue;
      }
      canvas
        ..save()
        ..clipRRect(rrect);
      for (var x = shape.rect.left.floor(); x < shape.rect.right.ceil(); x++) {
        final depth = Skeleton.breathAt(
          phase.value,
          (x + 0.5) / size.width,
          SkeletonBreath.gentleSweep,
        );
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), shape.rect.top, 1, shape.rect.height),
          Paint()..color = color.withValues(alpha: color.a * depth),
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Reference old) => true;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('breathing looks like its definition (${brightness.name})', (
      tester,
    ) async {
      tester.view
        ..physicalSize = _size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final skeleton = GlobalKey();
      final reference = GlobalKey();
      final phase = ValueNotifier<double>(0);
      addTearDown(phase.dispose);
      final theme = ThemeData(brightness: brightness);
      final background = theme.colorScheme.surface;
      final card = brightness == Brightness.dark
          ? const Color(0xFF2C2C2E)
          : const Color(0xFFF2F2F7);

      // 照定義畫的那張墊在骨架底下、同一個位置，各自畫成圖來比：骨架一直
      // 在元件樹裡，呼吸不會重來。
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) => Stack(
              children: [
                RepaintBoundary(
                  key: reference,
                  child: ColoredBox(
                    color: background,
                    child: CustomPaint(
                      size: _size,
                      painter: _Reference(
                        _shapes(card),
                        Skeleton.colorOf(context),
                        phase,
                      ),
                    ),
                  ),
                ),
                RepaintBoundary(
                  key: skeleton,
                  child: ColoredBox(
                    color: background,
                    child: SizedBox.fromSize(
                      size: _size,
                      child: _skeleton(card),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      Future<Uint8List> pixels(GlobalKey boundary) async =>
          (await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            image.dispose();
            return data!.buffer.asUint8List();
          }))!;

      // 呼吸從第一個 tick 起算：先推一幀讓它開始，之後經過的時間就是相位。
      await tester.pump();
      var elapsed = Duration.zero;
      for (final at in const [0, 300, 700, 1100, 1500]) {
        final step = Duration(milliseconds: at) - elapsed;
        elapsed += step;
        phase.value =
            elapsed.inMicroseconds / Skeleton.breathCycle.inMicroseconds;
        await tester.pump(step);
        final actual = await pixels(skeleton);
        final expected = await pixels(reference);

        var max = 0;
        var worst = Offset.zero;
        for (var i = 0; i < actual.length; i += 4) {
          for (var c = 0; c < 3; c++) {
            final d = (actual[i + c] - expected[i + c]).abs();
            if (d > max) {
              max = d;
              worst = Offset(
                (i ~/ 4 % _size.width).toDouble(),
                (i ~/ 4 ~/ _size.width).toDouble(),
              );
            }
          }
        }
        expect(
          max,
          lessThanOrEqualTo(_tolerance),
          reason: '${at}ms 時最多差 $max 階，在 $worst',
        );
      }
    });
  }
}
