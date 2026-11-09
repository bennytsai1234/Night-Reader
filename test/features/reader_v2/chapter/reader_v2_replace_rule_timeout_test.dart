import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';

/// 每一章都是一行 30 個 a 接一個「!」，回溯規則遇到就跑不完。
class _Site extends BookSourceService {
  /// 只給廣告那一行，回溯規則很快就跑完。
  bool plain = false;

  /// 設了就等它結束再回覆（重新取得本章用）。
  Completer<void>? refetchGate;

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
    bool keepImages = false,
  }) async {
    final gate = refetchGate;
    if (gate != null) {
      refetchGate = null;
      await gate.future;
    }
    return plain
        ? '${chapter.title}的廣告。'
        : '${chapter.title}的廣告。\n${'a' * 30}!';
  }
}

class _SourceDao extends Fake implements BookSourceDao {
  _SourceDao(this.source);

  final BookSource source;

  @override
  Future<BookSource?> getByUrl(String url) async => source;
}

void main() {
  late AppDatabase db;
  late _Site site;
  late ReplaceRuleDao replaceDao;
  late ReaderV2ChapterRepository repository;
  late List<ReplaceRule> disabled;

  final source = BookSource.fromJson({
    'bookSourceName': '測試',
    'bookSourceUrl': 'https://s.example',
  });
  final book = Book(
    bookUrl: 'https://s.example/book/1',
    origin: 'https://s.example',
    name: '書',
  );
  final chapters = [
    for (var i = 0; i < 2; i++)
      BookChapter(
        url: 'https://s.example/c/$i.html',
        title: '第${i + 1}章',
        bookUrl: book.bookUrl,
        index: i,
      ),
  ];

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    replaceDao = ReplaceRuleDao(db);
    await replaceDao.insert(
      ReplaceRule(
        name: '回溯',
        pattern: r'(?m)^(a+)+$',
        replacement: 'x',
        timeoutMillisecond: 200,
        order: 1,
      ),
    );
    await replaceDao.insert(
      ReplaceRule(
        name: '去廣告',
        pattern: '的廣告',
        replacement: '',
        isRegex: false,
        order: 2,
      ),
    );
    final chapterDao = ChapterDao(db);
    await chapterDao.insertChapters(chapters);
    disabled = [];
    site = _Site();
    repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: chapters,
      bookDao: BookDao(db),
      chapterDao: chapterDao,
      replaceDao: replaceDao,
      sourceDao: _SourceDao(source),
      contentDao: ReaderChapterContentDao(db),
      service: site,
      onReplaceRuleDisabled: disabled.add,
    );
  });

  tearDown(() async {
    repository.dispose();
    await db.close();
  });

  test('跑太久的規則被停用，這一章照其他規則套完照常顯示', () async {
    final content = await repository.loadContent(0);

    expect(content.plainText, contains('第1章。'));
    expect(content.plainText, contains('${'a' * 30}!'));
    expect(disabled.map((rule) => rule.name), ['回溯']);
    final rules = await replaceDao.getAll();
    expect(
      {for (final rule in rules) rule.name: rule.isEnabled},
      {'回溯': false, '去廣告': true},
    );
  });

  test('閱讀器關掉後才逾時的規則不停用：說不了，下次開書再停用並提示', () async {
    final load = repository.loadContent(0);
    repository.dispose();
    try {
      await load;
    } catch (_) {
      // 關掉後這一章載不載得完都不要緊。
    }

    expect(disabled, isEmpty);
    final rules = await replaceDao.getAll();
    expect(rules.every((rule) => rule.isEnabled), isTrue);
  });

  test('之後的章不再跑那一條', () async {
    await repository.loadContent(0);
    final next = await repository.loadContent(1);

    expect(next.plainText, contains('第2章。'));
    expect(disabled.map((rule) => rule.name), ['回溯']);
  });

  test('另一個閱讀器同時在處理的章也收到停用，之後不再跑那一條', () async {
    final other = <ReplaceRule>[];
    final second = ReaderV2ChapterRepository(
      book: book,
      initialChapters: chapters,
      bookDao: BookDao(db),
      chapterDao: ChapterDao(db),
      replaceDao: replaceDao,
      sourceDao: _SourceDao(source),
      contentDao: ReaderChapterContentDao(db),
      service: _Site(),
      onReplaceRuleDisabled: other.add,
    );
    addTearDown(second.dispose);
    // 兩邊同時處理第 1 章，都帶著「回溯」：先跑的那一章逾時，排在後面的
    // 那一章拿掉它重送。兩個閱讀器都要知道它停用了。
    await Future.wait([repository.loadContent(0), second.loadContent(0)]);
    expect(disabled.map((rule) => rule.name), ['回溯']);
    expect(other.map((rule) => rule.name), ['回溯']);

    disabled.clear();
    other.clear();
    await second.loadContent(1);
    expect(other, isEmpty);
  });

  test('重載失敗時不放回途中被停用的規則', () async {
    // 規則快取裡有「回溯」（它只對 a 開頭的行跑，第 1 章先不給 a）。
    site.plain = true;
    await repository.loadContent(0);
    site.plain = false;

    // 重新取得本章時，規則在別處被停用（例如另一個閱讀器），之後重新取得失敗。
    final gate = site.refetchGate = Completer<void>();
    final reload = repository.reloadContent(0, refetch: true);
    final backtracking = (await replaceDao.getAll()).firstWhere(
      (rule) => rule.name == '回溯',
    );
    await replaceDao.updateEnabled(backtracking.id, false);
    await Future<void>.delayed(Duration.zero);
    gate.completeError(StateError('連不上'));
    await expectLater(reload, throwsA(anything));

    final next = await repository.loadContent(1);
    expect(next.plainText, contains('第2章。'));
    expect(disabled, isEmpty);
  });
}
