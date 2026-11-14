/// 用真的書源與使用者自己的 AI 服務跑 AI 找書（ADR 0060），一件一個描述，
/// 看每件走了幾輪、花多久、交出什麼；迭代找書的工具與提示詞時拿來比前後
/// （`docs/agents/ai-find-runs.md`）。會呼叫 AI 服務、花使用者的額度。
///
/// ```sh
/// NR_SOURCES=<書源 JSON> NR_CASES=test/live/ai_find_cases.json \
///   NR_AI_KEY_FILE=<只放金鑰的檔> NR_OUT=<結果 JSON> \
///   tool/flutter_test.sh --run-skipped -t live test/live/ai_find_live_test.dart
/// ```
///
/// - `NR_SOURCES` 是使用者的整份匯出檔，整份存進暫存資料庫，搜尋範圍是全部
///   書源（同搜尋頁預設）。
/// - `NR_CASES` 是案件集：每件 `id`、`description`、`depth`（quick、normal、
///   deep），可以有 `shelf`（書架與閱讀紀錄，欄位同 `AiFindShelfEntry`，
///   `kind` 寫 novel、comic、audio）。`NR_ONLY=<id,id>` 只跑這幾件。
/// - 只給 `NR_SEARCH=<關鍵字>`、不給 `NR_CASES` 時不問 AI：照找書的搜尋工具
///   搜一次，印出送了幾個書源、幾個出錯、花多久、搜到幾本（量一次搜尋要等
///   多久用）。`NR_SEARCH_KIND` 給 comic、audio 換類別。
/// - `NR_AI_URL`、`NR_AI_MODEL`、`NR_AI_EFFORT` 同修書源的實跑
///   （`docs/agents/ai-repair-runs.md`）。
/// - 一件接一件跑：每件的搜尋都送全部書源，同時跑會互搶書源 isolate，量到
///   的時間不是使用者會碰到的。
/// - 每件的完整紀錄寫在最後印出的資料夾，統計那一行開頭是
///   `NR-AI-FIND-STATS`。
///
/// 書源的拿法同 `source_check_live_test.dart` 檔頭。金鑰固定放在主資料夾的
/// `.local/ai-repair.key`（git 忽略、不上傳）。
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/ai_find/ai_find_library.dart';
import 'package:night_reader/core/ai_find/ai_find_prompt.dart';
import 'package:night_reader/core/ai_find/ai_find_session.dart';
import 'package:night_reader/core/ai_repair/ai_repair_log.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/features/search/ai_find/app_ai_find_library.dart';
import 'package:night_reader/features/search/models/search_scope.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;
  static _MinimalServicesBinding ensureInitialized() =>
      _instance ??= _MinimalServicesBinding();
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

/// 正式書庫，書架換成案件給的那一份（暫存資料庫裡沒有書架）。
class _CaseLibrary implements AiFindLibrary {
  _CaseLibrary(this._real, this._shelf);
  final AppAiFindLibrary _real;
  final List<AiFindShelfEntry> _shelf;

  @override
  Future<AiFindSearchResult> search(
    String keyword,
    BookSourceKind kind,
    CancelToken cancelToken,
  ) => _real.search(keyword, kind, cancelToken);

  @override
  Future<Book> detail(SearchBook book, CancelToken cancelToken) =>
      _real.detail(book, cancelToken);

  @override
  Future<AiFindChapter> chapter(
    SearchBook book,
    int number,
    CancelToken cancelToken,
  ) => _real.chapter(book, number, cancelToken);

  @override
  Future<List<AiFindExploreSource>> exploreSources() => _real.exploreSources();

  @override
  Future<List<String>> exploreCategories(
    AiFindExploreSource source,
    CancelToken cancelToken,
  ) => _real.exploreCategories(source, cancelToken);

  @override
  Future<List<SearchBook>> exploreBooks(
    AiFindExploreSource source,
    int category,
    int page,
    CancelToken cancelToken,
  ) => _real.exploreBooks(source, category, page, cancelToken);

  @override
  Future<List<AiFindShelfEntry>> shelf() async => _shelf;

  @override
  Set<String> get secrets => _real.secrets;
}

const Map<String, BookSourceKind> _kinds = {
  'novel': BookSourceKind.novel,
  'comic': BookSourceKind.comic,
  'audio': BookSourceKind.audio,
};

List<AiFindShelfEntry> _shelfOf(Object? json) => [
  for (final item in (json as List?) ?? const [])
    (
      name: (item as Map)['name'] as String,
      author: item['author'] as String? ?? '',
      kind: _kinds[item['kind']],
      onShelf: item['onShelf'] as bool? ?? true,
      local: item['local'] as bool? ?? false,
      readSeconds: item['readSeconds'] as int? ?? 0,
      chapter: item['chapter'] as String?,
      chapterIndex: item['chapterIndex'] as int?,
      chapterTotal: item['chapterTotal'] as int?,
    ),
];

void main() {
  _MinimalServicesBinding.ensureInitialized();
  final root = Directory.systemTemp.createTempSync('night_reader_ai_find_');
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
  });

  final env = Platform.environment;
  final path = env['NR_SOURCES'];
  if (path == null) return;
  final sources = [
    for (final json in (jsonDecode(File(path).readAsStringSync()) as List))
      BookSource.fromJson(json as Map<String, dynamic>),
  ];
  final casesPath = env['NR_CASES'];
  final searchOnly = env['NR_SEARCH'];

  if (casesPath == null) {
    if (searchOnly == null) throw StateError('要給 NR_CASES 或 NR_SEARCH');
    test('只搜一次「$searchOnly」', () async {
      await getIt<BookSourceDao>().upsertAll(sources);
      final kind = _kinds[env['NR_SEARCH_KIND'] ?? 'novel']!;
      final library = AppAiFindLibrary(scope: SearchScope());
      final watch = Stopwatch()..start();
      final result = await library.search(searchOnly, kind, CancelToken());
      debugPrint(
        '##### 搜尋「$searchOnly」${kind.name}：送了 ${result.sources} 個書源，'
        '${result.failed} 個出錯或逾時，花 '
        '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} 秒，'
        '合併後 ${result.books.length} 本',
      );
      for (final book in result.books.take(10)) {
        debugPrint(
          '#####   ${book.name}｜${book.author}｜${book.origins.length} 個書源',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 20)));
    return;
  }

  final key = File(env['NR_AI_KEY_FILE']!).readAsStringSync().trim();
  final out = env['NR_OUT']!;
  final only = env['NR_ONLY']?.split(',').map((id) => id.trim()).toSet();
  final cases = [
    for (final item
        in (jsonDecode(File(casesPath).readAsStringSync())
                as Map<String, dynamic>)['cases']
            as List)
      if (only == null || only.contains((item as Map)['id']))
        item as Map<String, dynamic>,
  ];
  final unmatched = {
    ...?only?.difference({for (final item in cases) item['id']}),
  };
  if (unmatched.isNotEmpty) {
    throw StateError('NR_ONLY 在案件集裡找不到：${unmatched.join('、')}');
  }
  if (cases.isEmpty) throw StateError('案件集裡沒有案件');

  test('AI 找書 ${cases.length} 件', () async {
    await getIt<BookSourceDao>().upsertAll(sources);
    final service = (
      baseUrl: env['NR_AI_URL'] ?? 'https://api.deepseek.com',
      apiKey: key,
      model: env['NR_AI_MODEL'] ?? 'deepseek-flash',
      effort: env['NR_AI_EFFORT'] ?? '',
    );
    final logs = '${(await CrashHandler.logDirectory()).path}/ai-repair';
    debugPrint('##### 完整找書紀錄：$logs');
    final rows = <Map<String, Object?>>[];
    final watch = Stopwatch()..start();
    for (final item in cases) {
      final id = item['id'] as String;
      final description = item['description'] as String;
      final session = AiFindSession(
        description: description,
        depth: AiFindDepth.fromName(item['depth'] as String?),
        library: _CaseLibrary(
          AppAiFindLibrary(scope: SearchScope()),
          _shelfOf(item['shelf']),
        ),
        ask: AiFindSession.askService(service),
        serviceLabel:
            '${Uri.tryParse(service.baseUrl)?.host ?? service.baseUrl} · '
            '${service.model} · 案件 $id',
        log: AiRepairLog.find(description: '[$id] $description'),
      );
      var lastRounds = 0;
      session.addListener(() {
        if (session.rounds.length != lastRounds) {
          lastRounds = session.rounds.length;
          debugPrint('##### $id 第 $lastRounds 輪');
        }
      });
      final caseWatch = Stopwatch()..start();
      await session.start();
      // 紀錄是排隊寫進檔案的：等最後幾段（結果、統計）寫完。
      final file = await session.log.file();
      final row = {
        'id': id,
        'description': description,
        'depth': session.depth.name,
        'outcome': session.outcome?.name,
        'failure': session.failure,
        'picks': [
          for (final pick in session.picks)
            {
              'name': pick.book.name,
              'author': pick.book.author,
              'origin': pick.book.originName,
              'reason': pick.reason,
            },
        ],
        'summary': session.summary,
        'tokens': session.tokens,
        'ms': caseWatch.elapsedMilliseconds,
        'stats': session.stats?.toMap(),
        'log': file?.path,
      };
      rows.add(row);
      debugPrint(
        '##### $id => ${row['outcome']} ${session.rounds.length} 輪 '
        '${(caseWatch.elapsedMilliseconds / 1000).round()} 秒 '
        '推薦 ${session.picks.map((p) => p.book.name).join('、')}'
        '${session.failure == null ? '' : '（${session.failure}）'}',
      );
      // 每件跑完就寫一次：整批中途停了，跑完的那幾件還在。
      File(out).writeAsStringSync(
        const JsonEncoder.withIndent('  ')
            .convert({'ms': watch.elapsedMilliseconds, 'items': rows}),
      );
      session.dispose();
    }
    debugPrint('##### 完整找書紀錄：$logs');
  }, timeout: const Timeout(Duration(hours: 3)));
}
