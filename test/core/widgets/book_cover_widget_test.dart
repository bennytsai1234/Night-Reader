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

  setUp(() async {
    BookCoverWidget.forgetFailedCovers();
    imageCache
      ..clear()
      ..clearLiveImages();
    dir = Directory.systemTemp.createTempSync('night_reader_cover_');
    final file = File('${dir.path}/cover.png')..writeAsBytesSync(_png);
    coverUrl = Uri.file(file.path).toString();
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
}
