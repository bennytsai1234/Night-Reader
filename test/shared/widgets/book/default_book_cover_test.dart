import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/shared/widgets/book/book_cover_widget.dart';
import 'package:night_reader/shared/widgets/book/default_book_cover.dart';

void main() {
  Future<Uint8List> pixelsOf(
    WidgetTester tester,
    BookSourceKind kind, {
    String bookName = '詭秘之主',
    Brightness brightness = Brightness.dark,
  }) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: boundary,
          child: SizedBox(
            width: 60,
            height: 84,
            // 深色畫夜空、淺色畫白天。
            child: Theme(
              data: ThemeData(brightness: brightness),
              child: DefaultBookCover(bookName: bookName, kind: kind),
            ),
          ),
        ),
      ),
    );
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return (await tester.runAsync(() async {
      final image = await render.toImage();
      final data = await image.toByteData();
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
  }

  testWidgets('漫畫、有聲書畫出和小說不同的夜空，同一類每次一樣', (tester) async {
    final novel = await pixelsOf(tester, BookSourceKind.novel);
    expect(await pixelsOf(tester, BookSourceKind.novel), novel);
    expect(await pixelsOf(tester, BookSourceKind.comic), isNot(novel));
    expect(await pixelsOf(tester, BookSourceKind.audio), isNot(novel));
    expect(await pixelsOf(tester, BookSourceKind.unsupported), novel);
  });

  testWidgets('不在書架上的兩本小說：白天同一片天（雲固定），夜空星星照書名', (tester) async {
    Future<Uint8List> of(String name, Brightness brightness) => pixelsOf(
      tester,
      BookSourceKind.novel,
      bookName: name,
      brightness: brightness,
    );
    expect(
      await of('星河彼岸', Brightness.light),
      await of('夜雨聽書', Brightness.light),
    );
    expect(
      await of('星河彼岸', Brightness.dark),
      isNot(await of('夜雨聽書', Brightness.dark)),
    );
  });

  testWidgets('有聲書的音量條照書名', (tester) async {
    expect(
      await pixelsOf(tester, BookSourceKind.audio, bookName: '星河彼岸'),
      isNot(await pixelsOf(tester, BookSourceKind.audio, bookName: '夜雨聽書')),
    );
  });

  testWidgets('沒有封面的書照它的類別畫預設封面', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: BookCoverWidget(bookName: '漫畫', kind: BookSourceKind.comic),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<DefaultBookCover>(find.byType(DefaultBookCover)).kind,
      BookSourceKind.comic,
    );
  });
}
