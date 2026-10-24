// 逐格錄影：動畫的候選給使用者在對話裡逐格比較（AGENTS.md「視覺由使用者在
// 圖上選」）。一格一格推進（16ms），每格記下畫面、這格在哪一段、主執行緒花了
// 多久（同 `frame_budget.dart`），之後用 `tool/frame_viewer/build.py` 做成
// 頁面。
//
// 在 `test/_screens/`（git 忽略）寫一個臨時測試，每個候選、淺色深色各錄一段，
// 名稱用「<候選>-<變化>-<light|dark>」（沒有變化就省略那一段，例如
// `beta-light`）：
//
//   testWidgets('launch', (tester) async {
//     setUpPhone(tester);
//     ...
//     await recordAnimation(
//       tester,
//       name: 'b1200-g100-light',
//       phase: () => ...,           // 這格在哪一段，例如「長出」「呼吸」
//       until: () => finished,      // 動畫播完
//       realAsync: true,            // 整個 App（資料庫在真的 isolate 裡）
//     );
//   });
//
// 跑法：`flutter test test/_screens/<檔名>_test.dart`。檔案寫在
// [frameRecordingDir]/<名稱>/：`frames.rgba`（每格原始像素接在一起，手機邏輯
// 尺寸）與 `meta.json`。量到的是電腦上 debug 模式的時間，看的是尖峰落在哪
// 一段，不是手機上的毫秒數；存畫面時讓出了真實時間，資料庫回應落在哪一格
// 會和只量成本時差一兩格。第一次開整個 App 含 debug 的編譯成本，先開一次
// 暖身再錄。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'frame_budget.dart';

/// 逐格錄影的輸出資料夾（系統暫存區，不在 repo 裡）。
final Directory frameRecordingDir = Directory(
  '${Directory.systemTemp.path}${Platform.pathSeparator}night-reader-frames',
);

/// 錄一段動畫，直到 [until] 成立後再多 [tailFrames] 格。[phase] 在每格畫完
/// 時回答畫面在哪一段（頁面上的色條與說明照它分段）。[onFrame]、
/// [realAsync] 同 [recordFrames]。
Future<void> recordAnimation(
  WidgetTester tester, {
  required String name,
  required String Function() phase,
  required bool Function() until,
  int tailFrames = 30,
  bool realAsync = false,
  Future<void> Function(int frame)? onFrame,
}) async {
  final dir = Directory(
    '${frameRecordingDir.path}${Platform.pathSeparator}$name',
  )..createSync(recursive: true);
  final raw = File('${dir.path}${Platform.pathSeparator}frames.rgba')
      .openSync(mode: FileMode.write);
  final phases = <String>[];
  var width = 0, height = 0;
  try {
    final costs = await recordFrames(
      tester,
      until: until,
      tailFrames: tailFrames,
      realAsync: realAsync,
      onFrame: onFrame,
      afterFrame: (_) async {
        phases.add(phase());
        var box = tester.renderObject(find.byType(View).first);
        while (!box.isRepaintBoundary) {
          box = box.parent!;
        }
        final layer = box.debugLayer! as OffsetLayer;
        // 根節點的範圍是實體像素：縮回手機的邏輯尺寸。
        final ratio = 1 / tester.view.devicePixelRatio;
        await tester.runAsync(() async {
          final image = await layer.toImage(box.paintBounds, pixelRatio: ratio);
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          width = image.width;
          height = image.height;
          image.dispose();
          raw.writeFromSync(bytes!.buffer.asUint8List());
        });
      },
    );
    File('${dir.path}${Platform.pathSeparator}meta.json').writeAsStringSync(
      jsonEncode({
        'width': width,
        'height': height,
        'frameMs': 16,
        'phases': phases,
        'costs': [for (final cost in costs) (cost.total / 100).round() / 10],
      }),
    );
  } finally {
    raw.closeSync();
  }
}
