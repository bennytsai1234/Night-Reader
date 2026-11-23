import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/shared/shelf_look.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() {
    ShelfLook.setShelfOrder(const []);
  });

  test('書架位置由上到下是 0 到 1，不在書架上的是 null', () {
    ShelfLook.setShelfOrder(['u1', 'u2', 'u3']);
    expect(ShelfLook.positionOf('u1'), 0);
    expect(ShelfLook.positionOf('u2'), 0.5);
    expect(ShelfLook.positionOf('u3'), 1);
    expect(ShelfLook.positionOf('u4'), isNull);
    expect(ShelfLook.positionOf(null), isNull);

    ShelfLook.setShelfOrder(['只有一本']);
    expect(ShelfLook.positionOf('只有一本'), 0);
  });

  test('換源換了網址，書架重讀前新網址沿用原本的位置', () {
    ShelfLook.setShelfOrder(['u1', 'u2', 'u3']);
    ShelfLook.bookSwitched(
      const BookSwitchedEvent(fromBookUrl: 'u1', toBookUrl: 'n1'),
    );
    expect(ShelfLook.positionOf('n1'), 0);
    expect(ShelfLook.positionOf('u1'), isNull);
    expect(ShelfLook.positionOf('u3'), 1);
  });

  test('開 App 讀偏好時清掉上一次的書架順序', () async {
    ShelfLook.setShelfOrder(['u1']);
    SharedPreferences.setMockInitialValues({PreferKey.shelfMergedList: true});
    ShelfLook.restore(await SharedPreferences.getInstance());
    expect(ShelfLook.mergedList.value, isTrue);
    expect(ShelfLook.positionOf('u1'), isNull);
    ShelfLook.mergedList.value = false;
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
