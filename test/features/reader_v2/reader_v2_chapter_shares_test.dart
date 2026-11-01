import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/features/reader_v2/hybrid/progress/chapter_shares.dart';
import 'package:night_reader/features/reader_v2/hybrid/progress/hybrid_progress.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

/// 全書進度照各章實際長度算，不照章數平均。
void main() {
  double bookPercent(ReaderV2ChapterShares? shares, int chapter, int offset) =>
      HybridProgress(chapterCount: 4, shares: shares)
          .progressForLocation(
            ReaderV2Location(chapterIndex: chapter, charOffset: offset),
            chapterLength: 100,
          )
          .bookPercent;

  test('沒有長度時和原本一樣照章數平均', () {
    expect(bookPercent(null, 2, 50), closeTo(62.5, 1e-9));
    expect(
      bookPercent(const ReaderV2ChapterShares.even(4), 2, 50),
      closeTo(62.5, 1e-9),
    );
  });

  test('照各章長度：長的一章佔得多', () {
    // 第一章 1000、其他三章各 100：讀完第一章已經是 1000/1300。
    final shares = ReaderV2ChapterShares.fromLengths([1000, 100, 100, 100]);
    expect(bookPercent(shares, 1, 0), closeTo(1000 / 1300 * 100, 1e-9));
    expect(bookPercent(shares, 0, 50), closeTo(500 / 1300 * 100, 1e-9));
    expect(bookPercent(shares, 3, 100), closeTo(100, 1e-9));
  });

  test('還沒下載的章照已下載的平均，分卷佔 0', () {
    final shares = ReaderV2ChapterShares.fromLengths([0, 300, null, 100]);
    // 已知平均 200：0 + 300 + 200 + 100 = 600。
    expect(shares.startOf(1), 0);
    expect(shares.shareOf(1), closeTo(0.5, 1e-9));
    expect(shares.startOf(3), closeTo(500 / 600, 1e-9));
    expect(shares.startOf(3) + shares.shareOf(3), closeTo(1, 1e-9));
  });

  test('資料庫讀得到每章正文的位元組數，失敗的與別本書的不算', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = ReaderChapterContentDao(db);
    Future<void> save(String book, String url, String content) =>
        dao.saveContent(
          contentKey: '$book$url',
          origin: 'o',
          bookUrl: book,
          chapterUrl: url,
          chapterIndex: 0,
          content: content,
          updatedAt: 0,
        );
    await save('b', 'c1', '雨是從傍晚開始下的。');
    await save('b', 'c2', 'abc');
    await save('other', 'c1', '別本書');
    await dao.saveFailure(
      contentKey: 'bc3',
      origin: 'o',
      bookUrl: 'b',
      chapterUrl: 'c3',
      chapterIndex: 2,
      message: '取不到',
      updatedAt: 0,
    );
    expect(await dao.getStoredContentBytes(origin: 'o', bookUrl: 'b'), {
      'c1': 30,
      'c2': 3,
    });
  });

  test('章數和目錄對不上（目錄剛更新）時照章數平均，不用舊的長度', () {
    final shares = ReaderV2ChapterShares.fromLengths([1000, 100, 100]);
    expect(bookPercent(shares, 2, 50), closeTo(62.5, 1e-9));
  });
}
