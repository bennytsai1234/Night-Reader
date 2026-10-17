import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/reader_skeleton_page.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  ReaderV2LayoutSpec spec({double fontSize = 18}) =>
      ReaderV2LayoutSpec.fromViewport(
        viewportSize: const Size(400, 800),
        style: ReaderV2LayoutStyle(
          fontSize: fontSize,
          lineHeight: 1.6,
          letterSpacing: 0,
          paragraphSpacing: 0.5,
          paddingTop: 0,
          paddingBottom: 0,
          paddingLeft: 20,
          paddingRight: 20,
          textIndent: 2,
        ),
      );

  ReaderSkeletonPage page({int charOffset = 120}) => ReaderSkeletonPage(
    chapterIndex: 3,
    charOffset: charOffset,
    visualOffsetPx: 4.5,
    layout: ReaderSkeletonPage.layoutKeyOf(spec()),
    lines: const [
      Rect.fromLTRB(56, 10.25, 380, 28.75),
      Rect.fromLTRB(20, 39, 210, 57),
    ],
    progress: const HybridProgressSnapshot(
      chapterIndex: 3,
      chapterCount: 40,
      chapterPercent: 35,
    ),
  );

  const location = ReaderV2Location(
    chapterIndex: 3,
    charOffset: 120,
    visualOffsetPx: 4.5,
  );

  test('only the same place in the same layout matches', () {
    expect(page().matches(location, spec()), isTrue);
    expect(
      page().matches(location.copyWith(visualOffsetPx: 4.7), spec()),
      isTrue,
      reason: '存回資料庫的小數誤差',
    );
    expect(page().matches(location.copyWith(charOffset: 121), spec()), isFalse);
    expect(page().matches(location, spec(fontSize: 19)), isFalse);
  });

  test('the layout key is the same on every launch', () {
    // 不能用 Object.hash：每次啟動 App 的雜湊種子不同。
    expect(
      ReaderSkeletonPage.layoutKeyOf(spec()),
      ReaderSkeletonPage.layoutKeyOf(spec()),
    );
    expect(ReaderSkeletonPage.layoutKeyOf(spec()), contains('18'));
  });

  test('a saved page reads back with one-decimal lines', () {
    final restored = ReaderSkeletonPage.fromJson(page().toJson());
    expect(restored.lines.first, const Rect.fromLTRB(56, 10.3, 380, 28.8));
    expect(restored.lines.last, const Rect.fromLTRB(20, 39, 210, 57));
    expect(restored.progress?.chapterPercent, 35);
    expect(restored.matches(location, spec()), isTrue);
  });

  group('store', () {
    late SharedPreferences prefs;
    late ReaderSkeletonPageStore store;
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      store = ReaderSkeletonPageStore(prefs);
    });

    test('keeps the latest page per book', () async {
      await store.write('a', page());
      await store.write('a', page(charOffset: 200));
      expect(store.read('a')?.charOffset, 200);
      expect(store.read('b'), isNull);
    });

    test('keeps only the most recently read books', () async {
      for (var i = 0; i < ReaderSkeletonPageStore.keptBooks + 2; i++) {
        await store.write('book$i', page());
      }
      // 再讀一次第 2 本：它變成最近的，不會被擠掉。
      await store.write('book2', page());
      await store.write('book99', page());
      expect(store.read('book0'), isNull);
      expect(store.read('book1'), isNull);
      expect(store.read('book3'), isNull);
      expect(store.read('book2'), isNotNull);
      expect(store.read('book99'), isNotNull);
    });

    test('an unreadable record reads as nothing', () async {
      await prefs.setString(ReaderSkeletonPageStore.key, 'not json');
      expect(store.read('a'), isNull);
      await store.write('a', page());
      expect(store.read('a'), isNotNull, reason: '寫入時整份換新');
    });
  });
}
