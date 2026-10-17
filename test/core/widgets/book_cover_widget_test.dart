import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

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
}
