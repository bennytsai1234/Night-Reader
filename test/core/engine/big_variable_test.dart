import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:path/path.dart' as p;

import '../../test_helper.dart';

/// 很長的變數照樣存在書與章節上，同步、備份帶著它；不另外寫檔（夜讀從來
/// 不讀那份檔案）。舊版寫下的資料夾開 App 後刪掉。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('big_variable');
    AppStoragePaths.useRoots((
      documents: root.path,
      support: root.path,
      temporary: root.path,
    ));
  });
  tearDown(() => root.delete(recursive: true));

  final big = 'x' * 6000;

  test('a long variable stays on the book and chapter, no file', () async {
    final book = Book(bookUrl: 'https://big.test/b');
    final chapter = BookChapter(
      url: 'https://big.test/c',
      bookUrl: book.bookUrl,
    );
    AnalyzeRule(
        source: BookSource(bookSourceUrl: 'https://big.test'),
        ruleData: book,
      )
      ..put('onBook', big)
      ..setChapter(chapter).put('onChapter', big);
    // 舊版寫檔不等它：給它時間寫完。
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(book.getVariable('onBook'), big);
    expect(chapter.getVariable('onChapter'), big);
    expect(Directory(p.join(root.path, 'ruleData')).existsSync(), isFalse);
  });

  test('the folder older versions wrote is removed', () async {
    final legacy = Directory(p.join(root.path, 'ruleData', 'book', 'a'))
      ..createSync(recursive: true);
    File(p.join(legacy.path, 'k.txt')).writeAsStringSync(big);

    await AppStoragePaths.removeLegacyRuleData();

    expect(Directory(p.join(root.path, 'ruleData')).existsSync(), isFalse);
  });
}
