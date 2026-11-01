// 開 App 骨架長出與呼吸的工作量與長相（ADR 0036）：證明骨架呼吸掉幀修好了
// 的框架裡不受量測雜訊影響的兩層。帶 `frame_budget` 標籤，平常的全套測試
// 跳過。
//
//   flutter test --run-skipped -t frame_budget test/frame_budget/launch_skeleton_work_test.dart
//   SKELETON_OUT=<資料夾> …   每一幀的工作量（work_<寬>x<高>.json）與畫面（PNG）存進去
//   SKELETON_BASE=<資料夾> …  和改前存的同一幀逐像素比
//
// 1. 工作量：手機（393 寬，書架 3 欄）與平板（1280 寬，7 欄）各開一次 App，
//    數骨架長出與呼吸的每一幀重畫了幾個骨架形狀
//    （[SkeletonBox.debugShapePaints]）。每一幀的工作要和書架上的方塊數
//    無關：兩種寬度裡每一幀最多重畫的形狀數要一樣。骨架長出的第一幀不算：
//    骨架第一次出現，總要畫一次。
// 2. 長相：長出與呼吸的每一幀照「從長出（呼吸）第一幀起的第幾幀」存成
//    PNG；給了 SKELETON_BASE 時和改前同一幀比，列出每段最多差幾階、哪幾幀
//    有像素差超過 [_tolerance]。時間是測試推的假時間，一幀 16ms，改前改後
//    同一幀的呼吸與長出進度一樣。
@Tags(['frame_budget'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/app_providers.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/main.dart';
import 'package:night_reader/shared/widgets/launch_entrance.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:provider/provider.dart';

import '../support/app_harness.dart';
import '../support/screenshot.dart';

const _frame = Duration(milliseconds: 16);

/// 改前改後同一個像素最多差幾階（0–255）還算一樣。
const _tolerance = 2;

const _sizes = {'phone': Size(393, 852), 'tablet': Size(1280, 880)};

/// 一幀：在哪一段、這一段的第幾幀、重畫了幾個骨架形狀。
class _Frame {
  _Frame(this.segment, this.index, this.paints);

  final String segment;
  final int index;
  final int paints;

  Map<String, Object> toJson() => {
    'segment': segment,
    'index': index,
    'paints': paints,
  };
}

/// 這一幀在進場的哪一段；進場還沒開始或已經開始換成內容時是 null。長完停
/// 拍定格畫面時頁首與分頁列會暫時換成真的（[LaunchEntranceMotion.revealed]），
/// 那幾幀還在長完停。
String? _segmentOf(LaunchEntranceMotion? entrance) {
  if (entrance == null || entrance.revealStarted) return null;
  final grow = entrance.skeleton;
  if (grow.value == 0) return null;
  if (!grow.isCompleted) return 'grow';
  return entrance.breathing.value ? 'breath' : 'settled';
}

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('skeleton work per frame does not grow with the shelf', (
    tester,
  ) async {
    final out = switch (Platform.environment['SKELETON_OUT']) {
      final path? => Directory(path),
      null => null,
    };
    final base = switch (Platform.environment['SKELETON_BASE']) {
      final path? => Directory(path),
      null => null,
    };
    // 一個邏輯像素一個像素：存圖、比圖都快。
    setUpScreenshot(tester, devicePixelRatio: 1);
    final covers = coverDirectory();
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      await seedMoreBooks(24);
      await seedCovers(covers);
      await out?.create(recursive: true);
    });

    final worst = <String, int>{};
    for (final MapEntry(key: name, value: size) in _sizes.entries) {
      tester.view
        ..physicalSize = size
        ..padding = const FakeViewPadding(top: 32, bottom: 24)
        ..viewPadding = const FakeViewPadding(top: 32, bottom: 24);
      await tester.pumpWidget(
        MultiProvider(
          providers: AppProviders.providers,
          child: const ReaderApp(),
        ),
      );
      final frames = <_Frame>[];
      final counts = <String, int>{};
      final diffs = <String, List<(int, int, int)>>{};
      for (var i = 0; i < 600; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        final before = SkeletonBox.debugShapePaints;
        await tester.pump(_frame);
        final paints = SkeletonBox.debugShapePaints - before;
        final shelf = find.byType(BookshelfPage).evaluate();
        final entrance = shelf.isEmpty
            ? null
            : LaunchEntrance.maybeOf(shelf.first);
        if (entrance?.revealStarted ?? false) break;
        final segment = _segmentOf(entrance);
        if (segment == null) continue;
        final index = counts[segment] = (counts[segment] ?? -1) + 1;
        frames.add(_Frame(segment, index, paints));
        if (segment == 'settled' || (out == null && base == null)) continue;
        final file = '${name}_${segment}_${index.toString().padLeft(3, '0')}';
        final pixels = await tester.runAsync(() => _capture(tester));
        if (out != null) {
          await tester.runAsync(
            () => _writePng(pixels!, size, '${out.path}/$file.png'),
          );
        }
        if (base != null) {
          final diff = await tester.runAsync(
            () => _compare(pixels!, size, '${base.path}/$file.png'),
          );
          if (diff != null) {
            (diffs[segment] ??= []).add((index, diff.$1, diff.$2));
          }
        }
      }
      if (out != null) {
        await tester.runAsync(
          () => File('${out.path}/work_$name.json').writeAsString(
            jsonEncode([for (final frame in frames) frame.toJson()]),
          ),
        );
      }

      for (final segment in ['grow', 'breath']) {
        final paints = [
          for (final frame in frames)
            if (frame.segment == segment &&
                !(segment == 'grow' && frame.index == 0))
              frame.paints,
        ];
        final first = frames
            .where((f) => f.segment == segment && f.index == 0)
            .map((f) => f.paints)
            .firstOrNull;
        final most = paints.isEmpty
            ? 0
            : paints.reduce((a, b) => a > b ? a : b);
        worst['$name/$segment'] = most;
        // ignore: avoid_print
        print(
          '$name $segment：${paints.length + (segment == 'grow' ? 1 : 0)} 幀，'
          '第一幀重畫 $first 個形狀，之後每幀最多 $most 個：$paints',
        );
        final segmentDiffs = diffs[segment];
        if (segmentDiffs != null) {
          final over = [
            for (final (index, max, count) in segmentDiffs)
              if (max > _tolerance) '第 $index 幀（最多差 $max 階，$count 個像素）',
          ];
          final max = segmentDiffs.fold(0, (m, d) => d.$2 > m ? d.$2 : m);
          // ignore: avoid_print
          print(
            '$name $segment 和改前比：${segmentDiffs.length} 幀，最多差 $max 階；'
            '${over.isEmpty ? '沒有超過 $_tolerance 階的幀' : over.join('、')}',
          );
        }
      }

      await tester.pumpWidget(const SizedBox.shrink());
      // 下載服務是單例，跨兩次開 App；等上一次排的工作跑完（同開 App 量測）。
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(seconds: 1));
      }
    }

    for (final segment in ['grow', 'breath']) {
      expect(
        worst['tablet/$segment'],
        worst['phone/$segment'],
        reason:
            '骨架${segment == 'grow' ? '長出' : '呼吸'}每一幀重畫的形狀數跟著'
            '書架的方塊數變多（手機 3 欄、平板 7 欄）',
      );
    }

    // 讓 App 留下的計時器（下載排程、重試）跑完，測試才能正常結束。
    await tester.pump(const Duration(minutes: 1));
  });
}

/// 整個畫面的像素（RGBA）。
Future<Uint8List> _capture(WidgetTester tester) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final image = await layer.toImage(Offset.zero & view.size);
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<void> _writePng(Uint8List pixels, Size size, String path) async {
  final image = await _decodeRaw(pixels, size);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  await File(path).writeAsBytes(png!.buffer.asUint8List());
}

Future<ui.Image> _decodeRaw(Uint8List pixels, Size size) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: size.width.toInt(),
    height: size.height.toInt(),
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return frame.image;
}

/// 和改前存的同一幀比：（最多差幾階、差超過 [_tolerance] 的像素數）；改前
/// 沒有這一幀時回傳 null。
Future<(int, int)?> _compare(Uint8List pixels, Size size, String path) async {
  final file = File(path);
  if (!file.existsSync()) return null;
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  final frame = await codec.getNextFrame();
  codec.dispose();
  final data = await frame.image.toByteData();
  frame.image.dispose();
  final old = data!.buffer.asUint8List();
  if (old.length != pixels.length) return (255, pixels.length ~/ 4);
  var max = 0, count = 0;
  for (var i = 0; i < pixels.length; i += 4) {
    var pixel = 0;
    for (var c = 0; c < 3; c++) {
      final d = (pixels[i + c] - old[i + c]).abs();
      if (d > pixel) pixel = d;
    }
    if (pixel > max) max = pixel;
    if (pixel > _tolerance) count++;
  }
  return (max, count);
}
