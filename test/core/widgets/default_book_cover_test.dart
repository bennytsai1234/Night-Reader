import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';

void main() {
  Future<Uint8List> pixelsOf(WidgetTester tester, BookSourceKind kind) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: boundary,
          child: SizedBox(
            width: 60,
            height: 84,
            child: DefaultBookCover(bookName: '詭秘之主', kind: kind),
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
}
