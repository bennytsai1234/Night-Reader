// 開 App 書架換場逐格對照（ADR 0029）：整個 App（記憶體資料庫、書架上的
// 書帶本機封面）開起來，每一格都拍下來。
//
// - 換場的每一格要等於「起點畫面與終點畫面照每個像素的橫向位置、同一條
//   曲線（[SkeletonReveal.incomingOpacityAt]）混合」，每個區域每個像素最多
//   差 2/255：頁首按鈕、標題、分頁列只要有自己的時機或曲線，或途中出現起點
//   與終點都沒有的樣子（例如按鈕褪掉一下），這裡就會差很多。
// - 換場每一格的離屏圖層、遮罩與不同強度的背景模糊，不能比換完之後靜止的
//   畫面多：手機上合成的成本測試量不到，數圖層量得到。
//
// 換場從哪一格開始不靠實作告訴我們：在骨架最後出現的那幾格附近找一個起點，
// 讓整個畫面和理想的混合最接近；同一個起點下每個區域都要對得上。

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/app_providers.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/main.dart';
import 'package:night_reader/shared/widgets/launch_entrance.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';
import 'package:provider/provider.dart';

import '../../support/app_harness.dart';
import '../../support/screenshot.dart';

const _width = 393.0;
const _height = 852.0;
const _frame = Duration(milliseconds: 16);

/// 一格畫面：像素（RGBA）與這一格圖層樹的合成負擔。
class _Shot {
  _Shot(
    this.pixels,
    this.load, {
    required this.skeleton,
    required this.entered,
  });

  final Uint8List pixels;
  final _Load load;

  /// 這一格的元件樹裡還有骨架。
  final bool skeleton;

  /// 骨架已經完全長出來（開 App 的進場播完）：換成內容的換場從這之後開始。
  final bool entered;
}

/// 會讓手機多開一張離屏畫布、或重新取樣底下畫面的圖層。
class _Load {
  const _Load({
    required this.opacity,
    required this.masks,
    required this.fullScreenMasks,
    required this.blurs,
    required this.blurStrengths,
  });

  final int opacity;
  final int masks;
  final int fullScreenMasks;
  final int blurs;
  final int blurStrengths;

  bool fitsIn(_Load rest) =>
      opacity <= rest.opacity &&
      masks <= rest.masks &&
      fullScreenMasks <= rest.fullScreenMasks &&
      blurs <= rest.blurs &&
      blurStrengths <= rest.blurStrengths;

  @override
  String toString() =>
      '半透明圖層 $opacity、遮罩 $masks（整個畫面 $fullScreenMasks）、'
      '背景模糊 $blurs（$blurStrengths 種強度）';
}

_Load _loadOf(Layer root) {
  var opacity = 0, masks = 0, fullScreen = 0, blurs = 0;
  final strengths = <String>{};
  void visit(Layer? layer) {
    for (; layer != null; layer = layer.nextSibling) {
      if (layer is OpacityLayer && (layer.alpha ?? 255) < 255) opacity++;
      if (layer is ShaderMaskLayer) {
        masks++;
        final rect = layer.maskRect;
        if (rect != null &&
            rect.width >= _width * 0.9 &&
            rect.height >= _height * 0.5) {
          fullScreen++;
        }
      }
      if (layer is BackdropFilterLayer && layer.filter != null) {
        blurs++;
        strengths.add(layer.filter.toString());
      }
      if (layer is ContainerLayer) visit(layer.firstChild);
    }
  }

  visit(root);
  return _Load(
    opacity: opacity,
    masks: masks,
    fullScreenMasks: fullScreen,
    blurs: blurs,
    blurStrengths: strengths.length,
  );
}

/// 畫面上的區域（邏輯像素，裝置像素比 1）。
const _regions = <String, Rect>{
  '頁首左鈕': Rect.fromLTRB(0, 32, 80, 76),
  '標題': Rect.fromLTRB(150, 32, 243, 76),
  '頁首右鈕': Rect.fromLTRB(313, 32, 393, 76),
  '書架': Rect.fromLTRB(16, 100, 377, 700),
  '分頁列': Rect.fromLTRB(16, 760, 320, 830),
  '搜尋鈕': Rect.fromLTRB(320, 760, 393, 830),
};

/// 一段換場的格數（0.6 秒，一格 16ms）。
final int _span =
    (SkeletonReveal.defaultDuration.inMicroseconds / _frame.inMicroseconds)
        .ceil();

/// 換場前靜止的格數：骨架在拍「之前」那一格就離開元件樹，之後畫面還靜止
/// hold 才開始掃（[LaunchEntranceMotion.hold]）。
final int _holdFrames =
    (LaunchEntranceMotion.hold.inMicroseconds / _frame.inMicroseconds).ceil();

/// 第 [k] 格（換場從第 [start] 格開始）每一行像素的理想濃度。
List<double> _alphas(int width, int k, int start) {
  final progress =
      ((k - start) *
              _frame.inMicroseconds /
              SkeletonReveal.defaultDuration.inMicroseconds)
          .clamp(0.0, 1.0);
  return [
    for (var x = 0; x < width; x++)
      SkeletonReveal.incomingOpacityAt(progress, (x + 0.5) / width),
  ];
}

void main() {
  for (final mode in ['light', 'dark']) {
    testWidgets('the launch reveal crossfades the whole screen left to right '
        'with no extra layers ($mode)', (tester) async {
      tester.view
        ..physicalSize = const Size(_width, _height)
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(top: 32, bottom: 24)
        ..viewPadding = const FakeViewPadding(top: 32, bottom: 24);
      addTearDown(tester.view.reset);
      setUpScreenshot(
        tester,
        size: const Size(_width, _height),
        devicePixelRatio: 1,
      );

      final covers = coverDirectory();
      await tester.runAsync(() async {
        await setUpApp(prefs: {'themeMode': mode});
        await seedLibrary(withContent: false);
        await seedCovers(covers);
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: AppProviders.providers,
          child: const ReaderApp(),
        ),
      );

      final shots = <_Shot>[];
      LaunchEntranceMotion? entrance;
      var sawSkeleton = false;
      var tail = -1;
      for (var i = 0; i < 600 && tail < _span + _holdFrames + 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(_frame);
        final view = tester.binding.renderViews.first;
        final layer = view.debugLayer! as OffsetLayer;
        final pixels = await tester.runAsync(() async {
          final image = await layer.toImage(Offset.zero & view.size);
          final data = await image.toByteData();
          image.dispose();
          return data!.buffer.asUint8List();
        });
        final skeleton = find.byType(SkeletonBox).evaluate().isNotEmpty;
        sawSkeleton |= skeleton;
        final shelfPage = find.byType(BookshelfPage).evaluate();
        if (shelfPage.isNotEmpty) {
          entrance ??= LaunchEntrance.maybeOf(shelfPage.first);
        }
        shots.add(
          _Shot(
            pixels!,
            _loadOf(layer),
            skeleton: skeleton,
            entered: entrance?.skeleton.isCompleted ?? false,
          ),
        );
        if (tail >= 0) {
          tail++;
        } else if (sawSkeleton && !skeleton) {
          tail = 0;
        }
      }
      expect(
        tail,
        greaterThanOrEqualTo(_span + _holdFrames + 12),
        reason: '換場要播完',
      );

      const width = 393, height = 852;
      final lastSkeleton = shots.lastIndexWhere((shot) => shot.skeleton);

      // 起點：在骨架最後出現的那一格附近，找讓整個畫面最接近理想混合的
      // 那一格（取樣每 3 像素一點）。
      double fitError(int start) {
        final from = shots[start].pixels;
        final to = shots[start + _span].pixels;
        var sum = 0.0;
        var count = 0;
        for (var k = start + 1; k < start + _span; k++) {
          final alphas = _alphas(width, k, start);
          final shot = shots[k].pixels;
          for (var y = 0; y < height; y += 3) {
            for (var x = 0; x < width; x += 3) {
              final i = (y * width + x) * 4;
              final a = alphas[x];
              for (var c = 0; c < 3; c++) {
                final ideal = from[i + c] * (1 - a) + to[i + c] * a;
                sum += (shot[i + c] - ideal).abs();
                count++;
              }
            }
          }
        }
        return sum / count;
      }

      // 起點那一格的書架還完全是骨架，離最後畫面還遠；換場播完之後的靜止
      // 畫面幾乎就是最後畫面。只拿來分這兩種：骨架停在最深時，深色比呼吸
      // 最淺時更接近書架（2026-10-23 量到約 86%），不能抓太緊。
      final shelf = _regions['書架']!;
      double distanceToEnd(int k) {
        final a = shots[k].pixels, b = shots.last.pixels;
        var sum = 0.0;
        var count = 0;
        for (var y = shelf.top.toInt(); y < shelf.bottom.toInt(); y += 3) {
          for (var x = shelf.left.toInt(); x < shelf.right.toInt(); x += 3) {
            final i = (y * width + x) * 4;
            for (var c = 0; c < 3; c++) {
              sum += (a[i + c] - b[i + c]).abs();
              count++;
            }
          }
        }
        return sum / count;
      }

      // 兩格畫面一模一樣：淺色的骨架呼吸一格只變 1/255，不能放寬。
      bool same(int a, int b) {
        final x = shots[a].pixels, y = shots[b].pixels;
        for (var i = 0; i < x.length; i++) {
          if (x[i] != y[i]) return false;
        }
        return true;
      }

      // 第 [s] 格是一段靜止畫面的最後一格：和上一格一樣、下一格就變了。
      bool stillEnds(int s) =>
          s > 0 && s + 1 < shots.length && same(s - 1, s) && !same(s, s + 1);

      // 骨架完全長出來之後才可能開始換成內容。
      final first = shots.indexWhere((shot) => shot.entered);
      // 骨架在拍「之前」那一格就離開元件樹，之後還靜止一段才掃：起點在
      // 骨架最後出現之後，一路找到錄影結束前一段換場；換場之後的靜止畫面
      // 已經接近最後畫面，下面照距離排除。
      final last = shots.length - _span - 1;
      expect(last, greaterThan(lastSkeleton));
      expect(first, inInclusiveRange(0, last));
      final distances = {
        for (var s = first; s <= last; s++) s: distanceToEnd(s),
      };
      final farthest = distances.values.reduce(math.max);
      var start = -1;
      var best = double.infinity;
      for (var s = first; s <= last; s++) {
        if (distances[s]! < farthest * 0.5) continue;
        // 起點在換場前靜止那一段的尾端附近：換場一開始濃度從左緣慢慢
        // 起步，頭兩三格的像素和靜止的畫面捨入成一樣，靜止段看起來會比
        // 真正的起點晚一兩格結束，由吻合度挑。呼吸到一半就開始換的話
        // 找不到起點。
        if (![for (var e = s - 1; e <= s + 4; e++) e].any(stillEnds)) {
          continue;
        }
        final error = fitError(s);
        if (error < best) {
          best = error;
          start = s;
        }
      }
      expect(start, greaterThanOrEqualTo(0), reason: '換場前要有靜止的畫面');

      // 換場前畫面靜止至少 hold：呼吸收住了才拍圖，拍圖那幾格落在靜止的
      // 畫面裡（LaunchEntranceMotion.rest、hold）。
      var stillFrom = start;
      while (stillFrom > 0 && same(stillFrom - 1, start)) {
        stillFrom--;
      }
      expect(
        (start - stillFrom) * _frame.inMicroseconds,
        greaterThanOrEqualTo(LaunchEntranceMotion.hold.inMicroseconds),
        reason: '換場前靜止了 ${start - stillFrom} 格',
      );

      // 同一個起點下，每一格、每個區域都要對得上。
      final from = shots[start].pixels;
      final to = shots[start + _span].pixels;
      final worst = <String, (int, int)>{};
      for (var k = start + 1; k < start + _span; k++) {
        final alphas = _alphas(width, k, start);
        final shot = shots[k].pixels;
        for (final MapEntry(key: name, value: rect) in _regions.entries) {
          for (var y = rect.top.toInt(); y < rect.bottom.toInt(); y++) {
            for (var x = rect.left.toInt(); x < rect.right.toInt(); x++) {
              final i = (y * width + x) * 4;
              final a = alphas[x];
              for (var c = 0; c < 3; c++) {
                final ideal = (from[i + c] * (1 - a) + to[i + c] * a).round();
                final diff = (shot[i + c] - ideal).abs();
                if (diff > (worst[name]?.$1 ?? 0)) worst[name] = (diff, k);
              }
            }
          }
        }
      }
      final off = {
        for (final MapEntry(key: name, value: (diff, k)) in worst.entries)
          if (diff > 2) name: '差 $diff/255（換場第 ${k - start} 格）',
      };

      // 換場每一格的合成負擔不比換完之後靜止的畫面多。
      final rest = shots[start + _span + 4].load;
      final heavier = [
        for (var k = start + 1; k < start + _span; k++)
          if (!shots[k].load.fitsIn(rest))
            '換場第 ${k - start} 格：${shots[k].load}',
      ];
      // 兩項一起看，舊的做法兩項各差在哪裡都列得出來。
      expect([
        for (final MapEntry(:key, :value) in off.entries) '不是照位置混合：$key $value',
        for (final line in heavier) '比靜止時（$rest）重：$line',
      ], isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, const Duration(seconds: 3));
      await tester.pump(const Duration(minutes: 1));
    });
  }
}
