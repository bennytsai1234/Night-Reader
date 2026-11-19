// 電腦上量繪製執行緒建字的貼圖（平移落在像素之間時補建的那種，
// docs/research/pixel-snap-text.md）。幀預算只量主執行緒，這裡補上繪製那一半。
//
// 跑法：`flutter test --enable-impeller --enable-vmservice <測試>`。測試平常不真的
// 畫（每幀交給引擎後不經過字貼圖）；開 Impeller 後，逐格錄影每格拍的畫面
// （`frame_recording.dart`）走和手機一樣的字貼圖，引擎的 `CreateGlyphAtlas`、
// `UpdateAtlasBitmap` 記進 Dart 的時間軸（Embedder）。
//
//   final clock = await GlyphAtlasClock.start(tester);
//   await paintOnce(tester);       // 靜止畫面的字先進字貼圖（手機上早就畫過）
//   await clock.reset(tester);
//   await action();
//   await recordAnimation(tester, name: name,
//       phase: () { clock.mark(); return ...; }, until: ...);
//   print(await clock.attach(tester, '${frameRecordingDir.path}/$name'));
//   await clock.dispose(tester);
//
// `attach` 把每格新字畫進字貼圖的時間寫進 meta.json 的 `glyph`，動畫儀表板多一排
// 「建字貼圖」。注意：
// - 字貼圖整個測試程序共用、只增不減：同一個程序裡先跑過的動畫，後面再跑就
//   看起來沒有成本。改前改後、第一次與再一次都要各自一個 `flutter test`，或在
//   同一個程序裡明確量「再一次」。
// - 不和 `FRAME_GC=1` 一起用：它會改掉時間軸的設定。
// - 時間軸整段錄完才取一次：每格拍圖都有一筆 `DoMakeRasterSnapshot`，`attach`
//   核對每一格都找得到，前面的被緩衝區蓋掉時直接失敗，不會靜靜地少算。
// - 時間是電腦上的：返回書架（#283 改前）電腦 28ms、手機 37ms，手機約慢 1.3 倍，
//   只當數量級。
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart' hide Timeline;
import 'package:vm_service/vm_service_io.dart';

class GlyphAtlasClock {
  GlyphAtlasClock._(this._vm);
  final VmService _vm;
  final List<int> _marks = [];

  static Future<GlyphAtlasClock> start(WidgetTester tester) async {
    final vm = (await tester.runAsync(() async {
      final http = (await Service.getInfo()).serverUri;
      if (http == null) {
        throw StateError(
          '量建字貼圖要加 --enable-impeller --enable-vmservice：'
          'flutter test --enable-impeller --enable-vmservice …',
        );
      }
      final path = http.path.endsWith('/') ? http.path : '${http.path}/';
      final vm = await vmServiceConnectUri(
        http.replace(scheme: 'ws', path: '${path}ws').toString(),
      );
      await vm.setVMTimelineFlags(['Embedder']);
      return vm;
    }))!;
    return GlyphAtlasClock._(vm);
  }

  Future<void> reset(WidgetTester tester) async {
    _marks.clear();
    await tester.runAsync(_vm.clearVMTimeline);
  }

  /// 關掉時間軸的 Embedder、斷開連線。
  Future<void> dispose(WidgetTester tester) async {
    await tester.runAsync(() async {
      await _vm.setVMTimelineFlags([]);
      await _vm.dispose();
    });
  }

  /// 每格畫完、拍圖之前叫（放在 recordAnimation 的 phase 裡）。
  void mark() => _marks.add(Timeline.now);

  /// 每格拍圖時：建字貼圖總時間（含沒有新字時的查找）、新字畫進貼圖的時間、
  /// 拍圖本身的時間（ms）。
  Future<({List<double> atlas, List<double> fresh, List<double> snapshot})>
  collect(WidgetTester tester) async {
    final tl = (await tester.runAsync(_vm.getVMTimeline))!;
    final n = _marks.length;
    final atlas = List<double>.filled(n, 0);
    final fresh = List<double>.filled(n, 0);
    final snapshot = List<double>.filled(n, 0);
    final open = <String, List<int>>{};
    int frameOf(int ts) {
      var i = -1;
      while (i + 1 < n && _marks[i + 1] <= ts) {
        i++;
      }
      return i;
    }

    for (final e in tl.traceEvents ?? const <TimelineEvent>[]) {
      final j = e.json!;
      final name = j['name'] as String? ?? '';
      final List<double>? into = name.contains('CreateGlyphAtlas')
          ? atlas
          : (name.endsWith('UpdateAtlasBitmap') ||
                name.endsWith('BulkUpdateAtlasBitmap'))
          ? fresh
          : name.contains('DoMakeRasterSnapshot')
          ? snapshot
          : null;
      if (into == null) continue;
      final key = '${j['tid']}/$name';
      final ts = j['ts'] as int;
      double? dur;
      if (j['ph'] == 'B') {
        (open[key] ??= []).add(ts);
      } else if (j['ph'] == 'E' && (open[key]?.isNotEmpty ?? false)) {
        final begin = open[key]!.removeLast();
        dur = (ts - begin) / 1000;
        final f = frameOf(begin);
        if (f >= 0) into[f] += dur;
      } else if (j['ph'] == 'X') {
        final f = frameOf(ts);
        if (f >= 0) into[f] += ((j['dur'] as int?) ?? 0) / 1000;
      }
    }
    return (atlas: atlas, fresh: fresh, snapshot: snapshot);
  }

  /// 把每格的字貼圖時間加進錄影的 meta.json（`glyph`：新字畫進貼圖的時間）。
  Future<String> attach(WidgetTester tester, String dir) async {
    final r = await collect(tester);
    final file = File('$dir${Platform.pathSeparator}meta.json');
    final meta = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final frames = (meta['phases'] as List).length;
    final missing = [
      for (var i = 0; i < frames && i < r.snapshot.length; i++)
        if (r.snapshot[i] == 0) i,
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        '第 ${missing.take(5).join('、')} 格找不到拍圖的事件：時間軸的緩衝區'
        '可能蓋掉了前面，這段的建字時間不可信（錄短一點再量）',
      );
    }
    double round(double v) => (v * 100).round() / 100;
    meta['glyph'] = [for (final v in r.fresh.take(frames)) round(v)];
    meta['glyphAtlas'] = [for (final v in r.atlas.take(frames)) round(v)];
    file.writeAsStringSync(jsonEncode(meta));
    final phases = (meta['phases'] as List).cast<String>();
    final byPhase = <String, double>{};
    final firstFrames = <String>[];
    for (var i = 0; i < frames && i < r.fresh.length; i++) {
      byPhase[phases[i]] = (byPhase[phases[i]] ?? 0) + r.fresh[i];
      if (r.fresh[i] > 0.05) {
        firstFrames.add('#$i(${phases[i]}) ${r.fresh[i].toStringAsFixed(2)}');
      }
    }
    return 'frames=$frames 新字 by phase: '
        '${byPhase.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(', ')}'
        '\n  frames with 新字: ${firstFrames.join('; ')}';
  }
}

/// 拍一張目前的畫面（不存）：讓畫面上的字先進字貼圖。
Future<void> paintOnce(WidgetTester tester) async {
  var box = tester.renderObject(find.byType(View).first);
  while (!box.isRepaintBoundary) {
    box = box.parent!;
  }
  final layer = box.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(box.paintBounds);
    image.dispose();
  });
}
