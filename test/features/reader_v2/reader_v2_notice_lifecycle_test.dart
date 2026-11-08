import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

import '../../support/app_harness.dart';

class _PendingBookmarkDao extends BookmarkDao {
  _PendingBookmarkDao(super.db);

  final Completer<Bookmark> completion = Completer<Bookmark>();
  Bookmark? received;

  @override
  Future<Bookmark> add(Bookmark bookmark) {
    received = bookmark;
    return completion.future;
  }
}

class _PendingHighlightDao extends HighlightDao {
  _PendingHighlightDao(super.db);

  final Completer<Highlight> completion = Completer<Highlight>();
  Highlight? received;

  @override
  Future<Highlight?> latest() async => null;

  @override
  Future<Highlight> add(Highlight highlight) {
    received = highlight;
    return completion.future;
  }
}

void main() {
  for (final succeeds in [true, false]) {
    testWidgets(
      '關閉閱讀器後書籤與標註儲存${succeeds ? '成功' : '失敗'}不再顯示提示',
      (tester) async {
        setUpPhone(tester);
        late final _PendingBookmarkDao bookmarks;
        late final _PendingHighlightDao highlights;
        await tester.runAsync(() async {
          await setUpApp();
          await seedLibrary();
          final db = getIt<AppDatabase>();
          bookmarks = _PendingBookmarkDao(db);
          highlights = _PendingHighlightDao(db);
          await getIt.unregister<BookmarkDao>();
          await getIt.unregister<HighlightDao>();
          getIt.registerSingleton<BookmarkDao>(bookmarks);
          getIt.registerSingleton<HighlightDao>(highlights);
        });

        await pumpApp(tester);
        await openReader(tester);

        final reader = tester.widget<HybridReaderScreen>(
          find.byType(HybridReaderScreen),
        );
        const location = ReaderV2Location(chapterIndex: 2, charOffset: 5);
        reader.onBookmarkText!((
          location: location,
          chapterTitle: '第三章',
          excerpt: '燈下的字句',
        ));
        reader.onHighlightText!((
          location: location,
          chapterTitle: '第三章',
          quote: '燈下的字句',
        ));
        await tester.pump();
        expect(bookmarks.received, isNotNull);
        expect(highlights.received, isNotNull);

        // 寫入還沒結束就關閉閱讀器，完成後不可再讀取已卸載的 context。
        await tester.pumpWidget(const SizedBox.shrink());
        if (succeeds) {
          bookmarks.completion.complete(bookmarks.received!.copyWith(id: 1));
          highlights.completion.complete(highlights.received!.copyWith(id: 2));
        } else {
          bookmarks.completion.completeError(StateError('書籤寫入失敗'));
          highlights.completion.completeError(StateError('標註寫入失敗'));
        }
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
