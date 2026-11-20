import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/shared/shelf_trial.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() {
    ShelfTrial.setShelfOrder(const []);
  });

  const novel = BookSourceKind.novel;
  const audio = BookSourceKind.audio;

  test('書架位置由上到下是 0 到 1，不在書架上的是 null', () {
    ShelfTrial.setShelfOrder([('甲', novel), ('乙', novel), ('丙', novel)]);
    expect(ShelfTrial.positionOf('甲', novel), 0);
    expect(ShelfTrial.positionOf('乙', novel), 0.5);
    expect(ShelfTrial.positionOf('丙', novel), 1);
    expect(ShelfTrial.positionOf('丁', novel), isNull);

    ShelfTrial.setShelfOrder([('只有一本', novel)]);
    expect(ShelfTrial.positionOf('只有一本', novel), 0);
  });

  test('同名的小說與有聲書各有自己的位置，不在書架上的那一類不借位置', () {
    ShelfTrial.setShelfOrder([('詭秘之主', novel), ('其他', novel), ('詭秘之主', audio)]);
    expect(ShelfTrial.positionOf('詭秘之主', novel), 0);
    expect(ShelfTrial.positionOf('詭秘之主', audio), 1);
    expect(ShelfTrial.positionOf('詭秘之主', BookSourceKind.comic), isNull);
  });

  test('開 App 讀偏好時清掉上一次的書架順序', () async {
    ShelfTrial.setShelfOrder([('甲', novel)]);
    SharedPreferences.setMockInitialValues({ShelfTrial.mergedListKey: true});
    ShelfTrial.restore(await SharedPreferences.getInstance());
    expect(ShelfTrial.mergedList.value, isTrue);
    expect(ShelfTrial.positionOf('甲', novel), isNull);
    ShelfTrial.mergedList.value = false;
  });

  test('列表併成一面時只有第一本上緣與最後一本下緣是圓角', () {
    const round = Radius.circular(AppGrouped.radius);
    expect(
      BookshelfListCard.mergedRadius(index: 0, count: 3),
      const BorderRadius.vertical(top: round),
    );
    expect(
      BookshelfListCard.mergedRadius(index: 1, count: 3),
      BorderRadius.zero,
    );
    expect(
      BookshelfListCard.mergedRadius(index: 2, count: 3),
      const BorderRadius.vertical(bottom: round),
    );
    expect(
      BookshelfListCard.mergedRadius(index: 0, count: 1),
      const BorderRadius.all(round),
    );
  });
}
