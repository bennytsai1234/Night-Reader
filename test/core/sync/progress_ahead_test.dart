import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/sync_records.dart';

Book _book({
  int chapterIndex = 0,
  int charOffset = 0,
  bool reversed = false,
  bool localComic = false,
}) => Book(
  bookUrl: 'https://src.example/b',
  name: '夜航',
  author: '某人',
  origin: localComic ? 'local' : 'src',
  type: localComic ? 2 : 0,
  isInBookshelf: true,
  chapterIndex: chapterIndex,
  charOffset: charOffset,
  readConfig: ReadConfig()..reverseToc = reversed,
  fileFingerprint: localComic ? 'print' : null,
);

SyncRecord _remote(
  int chapterIndex,
  int charOffset, {
  String title = '',
  String chapterId = '',
  bool? tocReversed = false,
  int time = 200,
}) => SyncRecord(
  time: time,
  data: {
    'chapterIndex': chapterIndex,
    'charOffset': charOffset,
    'chapterTitle': title,
    'chapterId': chapterId,
    'tocReversed': tocReversed,
  },
);

void main() {
  const titles = ['序', '第一章', '第二章', '第三章'];

  test('a later chapter, or more characters in the same chapter, is ahead', () {
    final book = _book(chapterIndex: 1, charOffset: 50);
    expect(
      ProgressSync.isAhead(
        book: book,
        remote: _remote(2, 0, title: '第二章'),
        titles: titles,
      ),
      isTrue,
    );
    expect(
      ProgressSync.isAhead(
        book: book,
        remote: _remote(1, 80, title: '第一章'),
        titles: titles,
      ),
      isTrue,
    );
  });

  test('the same position or an earlier one is not ahead', () {
    final book = _book(chapterIndex: 1, charOffset: 50);
    expect(
      ProgressSync.isAhead(
        book: book,
        remote: _remote(1, 50, title: '第一章'),
        titles: titles,
      ),
      isFalse,
    );
    expect(
      ProgressSync.isAhead(
        book: book,
        remote: _remote(1, 20, title: '第一章'),
        titles: titles,
      ),
      isFalse,
    );
    expect(
      ProgressSync.isAhead(
        book: book,
        remote: _remote(0, 500, title: '序'),
        titles: titles,
      ),
      isFalse,
    );
  });

  test('a local comic is matched by the chapter fingerprint', () {
    final book = _book(chapterIndex: 0, charOffset: 3, localComic: true);
    const ids = ['c1', 'c2'];
    expect(
      ProgressSync.isAhead(
        book: book,
        remote: _remote(0, 0, title: '不同的章名', chapterId: 'c2'),
        titles: const ['第1話', '第2話'],
        ids: ids,
      ),
      isTrue,
    );
    expect(
      ProgressSync.isAhead(
        book: book,
        remote: _remote(0, 1, title: '不同的章名', chapterId: 'c1'),
        titles: const ['第1話', '第2話'],
        ids: ids,
      ),
      isFalse,
    );
  });

  test('a reversed table of contents counts in reading order', () {
    // 這台反轉了：存著的目錄是閱讀順序，另一台沒反轉的序號要先從另一頭數。
    final book = _book(chapterIndex: 0, charOffset: 0, reversed: true);
    const reversedTitles = ['a', 'b', 'c', 'd'];
    expect(
      ProgressSync.isAhead(
        book: book,
        remote: _remote(1, 0, tocReversed: false),
        titles: reversedTitles,
      ),
      isTrue,
      reason: '另一台的序號 1 從這台的方向數是 2，在讀到的地方後面',
    );
    expect(
      ProgressSync.isAhead(
        book: book,
        remote: _remote(3, 0, tocReversed: false),
        titles: reversedTitles,
      ),
      isFalse,
      reason: '另一台的序號 3 從這台的方向數是 0，和這台一樣',
    );
    expect(
      ProgressSync.isAhead(
        book: book,
        remote: _remote(1, 0, tocReversed: true),
        titles: reversedTitles,
      ),
      isTrue,
      reason: '兩台同一個方向，序號 1 在序號 0 後面',
    );
  });
}
