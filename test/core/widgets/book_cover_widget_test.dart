import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file/local.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/shared/widgets/cover_reveal.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';

/// 1×1 的 PNG。
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, //
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, //
  0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB0, 0x00, 0x00, 0x00, //
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

void main() {
  late Directory dir;
  late String coverUrl;
  late String otherUrl;

  setUp(() async {
    BookCoverWidget.forgetFailedCovers();
    imageCache
      ..clear()
      ..clearLiveImages();
    dir = Directory.systemTemp.createTempSync('night_reader_cover_');
    final file = File('${dir.path}/cover.png')..writeAsBytesSync(_png);
    coverUrl = Uri.file(file.path).toString();
    final other = File('${dir.path}/other.png')..writeAsBytesSync(_png);
    otherUrl = Uri.file(other.path).toString();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Widget cover(String? url) => MaterialApp(
    home: Center(
      child: BookCoverWidget(bookName: '書', coverUrl: url),
    ),
  );

  /// 讓檔案讀取與解碼在真實事件迴圈上跑完，再畫出來。
  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  /// 離某個元件最近的 [FadeTransition] 此刻的透明度。
  double opacityAbove(WidgetTester tester, Finder finder) => tester
      .widget<FadeTransition>(
        find.ancestor(of: finder, matching: find.byType(FadeTransition)).first,
      )
      .opacity
      .value;

  /// 換封面時每張封面是一層（以來源為 key），這一層此刻的透明度。
  double layerOpacity(WidgetTester tester, Finder finder) {
    final layer = find
        .ancestor(
          of: finder,
          matching: find.byWidgetPredicate(
            (w) => w is KeyedSubtree && w.key is ValueKey<(String, String?)>,
          ),
        )
        .first;
    return tester
        .widget<FadeTransition>(
          find
              .descendant(of: layer, matching: find.byType(FadeTransition))
              .first,
        )
        .opacity
        .value;
  }

  /// 某個來源那一層的封面圖。
  Finder imageOf(String url) => find.descendant(
    of: find.byWidgetPredicate(
      (w) =>
          w is KeyedSubtree &&
          w.key == ValueKey<(String, String?)>(('cover', url)),
    ),
    matching: find.byType(RawImage),
  );

  testWidgets('a cover that fails to load fades the default cover in', (
    tester,
  ) async {
    await tester.pumpWidget(
      cover(Uri.file('${dir.path}/missing.png').toString()),
    );
    expect(find.byType(DefaultBookCover), findsNothing);
    await settleIo(tester);

    expect(find.byType(DefaultBookCover), findsOneWidget);
    expect(opacityAbove(tester, find.byType(DefaultBookCover)), lessThan(1));
    await tester.pump(AppMotion.fade ~/ 2);
    expect(
      opacityAbove(tester, find.byType(DefaultBookCover)),
      inExclusiveRange(0, 1),
    );
    await tester.pumpAndSettle();
    expect(opacityAbove(tester, find.byType(DefaultBookCover)), 1);
  });

  testWidgets('switching to the default cover crossfades', (tester) async {
    await tester.pumpWidget(cover(coverUrl));
    await settleIo(tester);
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.byType(DefaultBookCover), findsNothing);

    await tester.pumpWidget(cover(null));
    await tester.pump(AppMotion.fade ~/ 2);
    // 舊封面還在底下，預設封面淡入到一半。
    expect(find.byType(RawImage), findsOneWidget);
    expect(
      layerOpacity(tester, find.byType(DefaultBookCover)),
      inExclusiveRange(0, 1),
    );

    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
    expect(layerOpacity(tester, find.byType(DefaultBookCover)), 1);
  });

  testWidgets('the old cover stays until the new one is decoded', (
    tester,
  ) async {
    await tester.pumpWidget(cover(null));
    await tester.pumpWidget(cover(coverUrl));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 新圖還沒讀好：舊封面照常畫著，新的那層全透明。
    expect(find.byType(DefaultBookCover), findsOneWidget);
    expect(layerOpacity(tester, find.byType(DefaultBookCover)), 1);
    expect(layerOpacity(tester, find.byType(RawImage)), 0);

    await settleIo(tester);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(DefaultBookCover), findsOneWidget);
    expect(layerOpacity(tester, find.byType(RawImage)), inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(find.byType(DefaultBookCover), findsNothing);
    expect(layerOpacity(tester, find.byType(RawImage)), 1);
  });

  testWidgets('a rebuild while the fallback fades in keeps fading', (
    tester,
  ) async {
    final missing = Uri.file('${dir.path}/missing.png').toString();
    await tester.pumpWidget(cover(missing));
    await settleIo(tester);
    await tester.pump(AppMotion.fade ~/ 4);
    final before = opacityAbove(tester, find.byType(DefaultBookCover));
    expect(before, inExclusiveRange(0, 1));

    // 父層因為別的原因重建（搜尋結果陸續進來）：淡入接著播，不會一下到位。
    await tester.pumpWidget(cover(missing));
    expect(opacityAbove(tester, find.byType(DefaultBookCover)), before);
    await tester.pump(AppMotion.fade ~/ 4);
    expect(
      opacityAbove(tester, find.byType(DefaultBookCover)),
      inExclusiveRange(before, 1),
    );
    await tester.pumpAndSettle();
    expect(opacityAbove(tester, find.byType(DefaultBookCover)), 1);
  });

  testWidgets('a known failed cover shows the default cover right away', (
    tester,
  ) async {
    final missing = Uri.file('${dir.path}/missing.png').toString();
    await tester.pumpWidget(cover(missing));
    await settleIo(tester);
    await tester.pumpAndSettle();

    // 換一個新的封面元件（例如清單重新建立）：記得載不到，不再重抓、不再淡。
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(cover(missing));
    expect(find.byType(DefaultBookCover), findsOneWidget);
    expect(opacityAbove(tester, find.byType(DefaultBookCover)), 1);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('switching back before the new cover decodes keeps the old one', (
    tester,
  ) async {
    await tester.pumpWidget(cover(null));
    await tester.pumpWidget(cover(coverUrl));
    await tester.pump(const Duration(milliseconds: 100));
    expect(layerOpacity(tester, find.byType(DefaultBookCover)), 1);

    // 新圖還沒解碼就切回來：畫面上本來就是預設封面，照常畫著、不重新淡入。
    await tester.pumpWidget(cover(null));
    expect(layerOpacity(tester, find.byType(DefaultBookCover)), 1);
    expect(find.byType(Image), findsNothing);
    await tester.pump(const Duration(milliseconds: 60));
    expect(layerOpacity(tester, find.byType(DefaultBookCover)), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('switching back mid-crossfade fades the new cover back out', (
    tester,
  ) async {
    await tester.pumpWidget(cover(null));
    await tester.pumpWidget(cover(coverUrl));
    await settleIo(tester);
    await tester.pump(AppMotion.fade ~/ 2);
    final half = layerOpacity(tester, imageOf(coverUrl));
    expect(half, inExclusiveRange(0, 1));

    await tester.pumpWidget(cover(null));
    // 從畫面上的樣子接著換：預設封面一直在底下，新圖從一半淡回去。
    expect(layerOpacity(tester, find.byType(DefaultBookCover)), 1);
    expect(layerOpacity(tester, imageOf(coverUrl)), half);
    await tester.pump(AppMotion.fade ~/ 2);
    expect(layerOpacity(tester, imageOf(coverUrl)), inExclusiveRange(0, half));

    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
    expect(layerOpacity(tester, find.byType(DefaultBookCover)), 1);
  });

  testWidgets('a third cover mid-crossfade continues from what is drawn', (
    tester,
  ) async {
    await tester.pumpWidget(cover(null));
    await tester.pumpWidget(cover(coverUrl));
    await settleIo(tester);
    await tester.pump(AppMotion.fade ~/ 2);
    final half = layerOpacity(tester, imageOf(coverUrl));
    expect(half, inExclusiveRange(0, 1));

    // 換到第三張：底下的預設封面與淡到一半的那張都照畫，新的解碼好才淡入。
    await tester.pumpWidget(cover(otherUrl));
    expect(layerOpacity(tester, find.byType(DefaultBookCover)), 1);
    expect(layerOpacity(tester, imageOf(coverUrl)), half);
    await tester.pump(const Duration(milliseconds: 100));
    expect(layerOpacity(tester, find.byType(DefaultBookCover)), 1);
    expect(layerOpacity(tester, imageOf(coverUrl)), half);

    await settleIo(tester);
    await tester.pump(AppMotion.fade ~/ 2);
    expect(layerOpacity(tester, imageOf(coverUrl)), half);
    expect(layerOpacity(tester, imageOf(otherUrl)), inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(find.byType(DefaultBookCover), findsNothing);
    expect(imageOf(coverUrl), findsNothing);
    expect(layerOpacity(tester, imageOf(otherUrl)), 1);
  });

  group('waiting for a page of covers', () {
    // 網路封面讀的是 CachedNetworkImageProvider 的磁碟快取；換成假的，測試
    // 決定哪些網址算已經在手機裡、什麼時候讀到（這個檔案裡其他測試不讀網路
    // 封面，不必換回去）。
    late _DiskCache cache;
    setUp(
      () =>
          CachedNetworkImageProvider.defaultCacheManager = cache = _DiskCache(),
    );

    Widget page({
      required bool loading,
      CoverWait wait = CoverWait.onDevice,
      List<String>? urls,
    }) => MaterialApp(
      home: Scaffold(
        body: SkeletonSwitcher(
          loading: loading,
          waitForCovers: wait,
          skeleton: const SkeletonBox(width: 40, height: 40),
          builder: (_) => Row(
            children: [
              for (final url in urls ?? [coverUrl, otherUrl])
                BookCoverWidget(bookName: '書', coverUrl: url),
            ],
          ),
        ),
      ),
    );

    const network = 'https://covers.example/a.jpg';

    double revealed(WidgetTester tester) => tester
        .widget<SkeletonRevealLayer>(find.byKey(const ValueKey('content')))
        .presence
        .value;

    bool allDrawn() => find
        .byType(RawImage)
        .evaluate()
        .every((element) => (element.widget as RawImage).image != null);

    testWidgets('covers already on the phone hold the reveal however slowly '
        'they decode, then appear with the page instead of fading in later', (
      tester,
    ) async {
      await tester.pumpWidget(page(loading: true));
      await tester.pumpWidget(page(loading: false));
      // 檔案還沒讀到（不讓出真實時間）：等多久都不換場，原本 300ms 就換了。
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(revealed(tester), 0, reason: '封面還畫不出來，骨架照常呼吸');
      expect(find.byType(SkeletonBox), findsOneWidget);

      // 讀到、解碼好：換場開始時兩張封面都已經畫得出來，之後不再各自淡入。
      var started = false;
      for (var i = 0; i < 200 && !started; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
        started = revealed(tester) > 0;
      }
      expect(started, isTrue);
      expect(find.byType(RawImage), findsNWidgets(2));
      expect(allDrawn(), isTrue, reason: '換場開始時封面都到位');
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        for (final fade in tester.renderObjectList<RenderAnimatedOpacity>(
          find.descendant(
            of: find.byType(BookCoverWidget),
            matching: find.byType(AnimatedOpacity),
          ),
        )) {
          expect(fade.opacity.value, 1, reason: '封面跟著整頁出現，不另外淡入');
        }
      }
      expect(find.byType(SkeletonBox), findsNothing);
    });

    testWidgets('a network cover already in the disk cache holds the reveal '
        'until it is drawn', (tester) async {
      cache.onDevice[network] = Uri.parse(coverUrl).toFilePath();
      await tester.pumpWidget(page(loading: true, urls: [network]));
      await tester.pumpWidget(page(loading: false, urls: [network]));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(revealed(tester), 0, reason: '手機裡有的封面讀得再慢都等');

      cache.release(network);
      var started = false;
      for (var i = 0; i < 200 && !started; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
        started = revealed(tester) > 0;
      }
      expect(started, isTrue);
      expect(allDrawn(), isTrue, reason: '換場開始時封面已經到位');
    });

    testWidgets('a network cover that is not on the phone does not hold the '
        'shelf', (tester) async {
      // 要上網抓：一直抓不到也不等。
      await tester.pumpWidget(page(loading: true, urls: [network]));
      await tester.pumpWidget(page(loading: false, urls: [network]));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(revealed(tester), greaterThan(0), reason: '要上網抓的封面不等');
    });

    testWidgets('other pages still wait briefly for any cover, network '
        'included, and let it fade in later', (tester) async {
      await tester.pumpWidget(
        page(loading: true, wait: CoverWait.brief, urls: [network]),
      );
      await tester.pumpWidget(
        page(loading: false, wait: CoverWait.brief, urls: [network]),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(revealed(tester), 0, reason: '最多等 0.3 秒，網路封面也等');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(revealed(tester), greaterThan(0), reason: '0.3 秒到了就換場');
    });
  });

  // 開 App 的書架在骨架底下一幀一步準備（CoverReveal.inSteps，ADR 0031）。
  group('a stepped reveal', () {
    Widget stepped(CoverReveal reveal, Widget child) => MaterialApp(
      home: CoverRevealScope(
        reveal: reveal,
        child: Center(child: child),
      ),
    );

    testWidgets('a cover already in the memory cache still waits for its own '
        'step after the card is first painted', (tester) async {
      await tester.pumpWidget(cover(coverUrl));
      await settleIo(tester);
      await tester.pumpWidget(const SizedBox.shrink());

      final reveal = CoverReveal(CoverWait.onDevice, inSteps: true);
      await tester.pumpWidget(
        stepped(
          reveal,
          CoverRevealSlot(
            child: BookCoverWidget(bookName: '書', coverUrl: coverUrl),
          ),
        ),
      );
      await tester.pump(); // 建書卡
      await tester.pump(); // 第一次畫書卡
      final raw = find.byType(RawImage);
      expect(tester.widget<RawImage>(raw).image, isNotNull);
      final gate = find.ancestor(
        of: raw,
        matching: find.byType(AnimatedOpacity),
      );
      expect(gate, findsOneWidget, reason: '快取裡的封面也要排隊換上');
      expect(tester.widget<AnimatedOpacity>(gate).opacity, 0);
      await tester.pump(); // 換上封面
      await tester.pump();
      expect(find.byType(AnimatedOpacity), findsNothing, reason: '換上後直接畫圖');
    });

    testWidgets('a show step left over from an earlier round cannot undo the '
        'current round, so the wait still ends', (tester) async {
      final a = CoverReveal(CoverWait.onDevice, inSteps: true);
      final b = CoverReveal(CoverWait.onDevice, inSteps: true)..add('另一張慢的封面');
      // a 的佇列前面塞滿別的步驟：這張封面在 a 的那一步很晚才輪到。
      for (var i = 0; i < 50; i++) {
        a.showCover(() {});
      }
      Widget page(CoverReveal reveal) =>
          stepped(reveal, BookCoverWidget(bookName: '書', coverUrl: coverUrl));
      await tester.pumpWidget(page(a));
      await settleIo(tester);
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );

      // 換一輪：b 先放行這張封面，a 排著的那一步之後才到。
      await tester.pumpWidget(page(b));
      var done = false;
      unawaited(b.settle().then((_) => done = true));
      for (var i = 0; i < 70; i++) {
        await tester.pump();
      }
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
      b.remove('另一張慢的封面');
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(done, isTrue, reason: '所有封面都換上了，等待要結束');
    });
  });
}

/// 網路封面的磁碟快取：[onDevice] 裡的網址算已經存在手機裡；讀取（不論
/// 從快取或網路）要等測試 [release] 才完成，不放行就一直讀不到。
class _DiskCache implements BaseCacheManager {
  /// 網址 → 快取檔案的路徑。
  final Map<String, String> onDevice = {};
  final Map<String, Completer<String>> _reads = {};

  void release(String url) =>
      (_reads[url] ??= Completer<String>()).complete(onDevice[url]);

  FileInfo _info(String path, String url) => FileInfo(
    const LocalFileSystem().file(path),
    FileSource.Cache,
    DateTime(2100),
    url,
  );

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    final path = onDevice[key];
    return path == null ? null : _info(path, key);
  }

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    final path = await (_reads[url] ??= Completer<String>()).future;
    yield _info(path, url);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
