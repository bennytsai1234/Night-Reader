/// 從真的網站抓幾章正文存成檔，給正文段落處理（段落修復、排版整理）比對
/// 改前改後用。書源 JSON 的來源與網路環境的坑見 `source_check_live_test.dart`
/// 檔頭與 `docs/agents/environment.md`。
///
/// ```sh
/// NR_SOURCES=<書源 JSON> NR_OUT_DIR=<資料夾> \
///   tool/flutter_test.sh --run-skipped -t live test/live/chapter_text_live_test.dart
/// ```
///
/// - `NR_ONLY=<書源名稱的一部分>`：只抓名稱含這段字的書源。
/// - `NR_LIMIT=<n>`：只抓前 n 個文字書源（預設 30）。
/// - `NR_KEYWORD`：搜尋關鍵字，預設「我的」。
/// - `NR_CHAPTERS`：抓目錄裡第幾章，逗號分隔，預設 `0,5,20`（超出目錄的略過）。
/// - `NR_PARALLEL`：同時抓幾個書源，預設 4。
///
/// 每章存成 `<NR_OUT_DIR>/<書源序號>-<章序號>.txt`，就是書源給的正文（存進
/// 資料庫前那份）；`index.jsonl` 每行一章：書源名稱、網址、書名、章名、檔名。
/// 比對段落修復用 `paragraph_repair_corpus_live_test.dart`。
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helper.dart';

/// 不用 TestWidgetsFlutterBinding：它會把網路請求都擋成 400。
class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

class _TempPaths extends PathProviderPlatform {
  _TempPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => root;
  @override
  Future<String?> getExternalStoragePath() async => root;
}

void main() {
  _MinimalServicesBinding.ensureInitialized();

  final root = Directory.systemTemp.createTempSync('night_reader_live_');
  setUpAll(() async {
    quickJsUnavailableReason();
    PathProviderPlatform.instance = _TempPaths(root.path);
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    registerDatabase(AppDatabase());
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    await NetworkService().init(ephemeral: true);
    SourceIsolate.enabled = true;
    SourceIsolate.start();
  });
  tearDownAll(() async {
    await SourceIsolate.stop();
    await AppDatabase().close();
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // 資料庫檔案在 Windows 上可能還被鎖著；暫存資料夾留給系統清。
    }
  });

  final env = Platform.environment;
  final path = env['NR_SOURCES'];
  final outDir = env['NR_OUT_DIR'];
  if (path == null || outDir == null) {
    test('NR_SOURCES', () => fail('用 NR_SOURCES 指定書源 JSON、NR_OUT_DIR 指定輸出'));
    return;
  }
  final only = env['NR_ONLY'];
  final limit = int.tryParse(env['NR_LIMIT'] ?? '') ?? 30;
  final keyword = env['NR_KEYWORD'] ?? '我的';
  final chapterIndexes = (env['NR_CHAPTERS'] ?? '0,5,20')
      .split(',')
      .map((part) => int.tryParse(part.trim()))
      .whereType<int>()
      .toList();
  final parallel = int.tryParse(env['NR_PARALLEL'] ?? '') ?? 4;
  final decoded = jsonDecode(File(path).readAsStringSync());
  final sources = [
    for (final json
        in (decoded is List ? decoded : [decoded]).cast<Map<String, dynamic>>())
      if ((json['bookSourceType'] as int? ?? 0) == 0 &&
          (only == null || (json['bookSourceName'] as String).contains(only)))
        json,
  ].take(limit).toList();
  final dir = Directory(outDir)..createSync(recursive: true);
  final index = File('${dir.path}/index.jsonl');
  final service = BookSourceService();

  Future<void> fetch(int sourceIndex, Map<String, dynamic> json) async {
    final source = BookSource.fromJson(json);
    final name = source.bookSourceName;
    try {
      final found = await service
          .searchBooks(source, keyword)
          .timeout(const Duration(seconds: 30));
      if (found.isEmpty) {
        debugPrint('##### $name => 搜尋沒有結果');
        return;
      }
      final book = await service
          .getBookInfo(
            source,
            found.first.toBook().copyWith(
              origin: source.bookSourceUrl,
              originName: name,
            ),
          )
          .timeout(const Duration(seconds: 30));
      final chapters =
          (await service
                  .getChapterList(source, book, chapterLimit: 40)
                  .timeout(const Duration(seconds: 40)))
              .where((chapter) => !chapter.isVolume)
              .toList();
      var saved = 0;
      for (final chapterIndex in chapterIndexes) {
        if (chapterIndex >= chapters.length) continue;
        final chapter = chapters[chapterIndex];
        final next = chapterIndex + 1 < chapters.length
            ? chapters[chapterIndex + 1].url
            : null;
        final String content;
        try {
          content = await service
              .getContent(source, book, chapter, nextChapterUrl: next)
              .timeout(const Duration(seconds: 40));
        } catch (e) {
          debugPrint('##### $name 第 $chapterIndex 章 => $e');
          continue;
        }
        if (content.trim().length < 200) continue;
        final file = '$sourceIndex-$chapterIndex.txt';
        File('${dir.path}/$file').writeAsStringSync(content, flush: true);
        index.writeAsStringSync(
          '${jsonEncode({'source': name, 'url': source.bookSourceUrl, 'book': book.name, 'chapter': chapter.title, 'file': file})}\n',
          mode: FileMode.append,
          flush: true,
        );
        saved++;
      }
      debugPrint('##### $name => 存了 $saved 章（${book.name}）');
    } catch (e) {
      debugPrint('##### $name => $e');
    }
  }

  test('${sources.length} 個書源', () async {
    var next = 0;
    Future<void> worker() async {
      while (next < sources.length) {
        final i = next++;
        await fetch(i, sources[i]);
      }
    }

    await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
  }, timeout: Timeout(Duration(minutes: 3 * sources.length ~/ parallel + 4)));
}
