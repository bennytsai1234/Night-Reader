import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/source_dedupe.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可以把讀清單卡住的 DAO。[gate] 卡在讀之前；[hold] 開著時每一次讀先讀好、
/// 回傳前各自卡在 [held] 的一個 completer，一個一個放行。
class _GatedDao extends BookSourceDao {
  _GatedDao(super.db);

  Completer<void>? gate;
  var hold = false;
  final held = <Completer<void>>[];

  @override
  Future<List<BookSource>> getAllPart() async {
    await gate?.future;
    final rows = await super.getAllPart();
    if (hold) {
      final release = Completer<void>();
      held.add(release);
      await release.future;
    }
    return rows;
  }
}

/// 寫進資料庫前卡住的匯入。[mergeSkipped] 時只寫進去、不併重複書源，像背景
/// 工作在跑時 [mergeDuplicateSources] 直接回傳。
class _GatedImport extends SourceImportService {
  _GatedImport(this._dao, {this.mergeSkipped = false}) : super(dao: _dao);

  final BookSourceDao _dao;
  final bool mergeSkipped;
  final gate = Completer<void>();

  @override
  Future<SourceImportCount> importSources(List<BookSource> sources) async {
    await gate.future;
    if (!mergeSkipped) return super.importSources(sources);
    await _dao.insertOrUpdateAll(sources);
    return (imported: sources.length, merged: 0);
  }
}

/// 卡住的併重複書源：[started] 在開始併時完成，[gate] 完成才真的併（重複的
/// 那幾個直接刪掉）。
class _GatedMerge {
  _GatedMerge(this.dao);

  final BookSourceDao dao;
  var started = Completer<void>();
  var gate = Completer<void>();
  var calls = 0;

  Future<int> call(List<BookSource> sources, {String? preferredUrl}) async {
    calls++;
    if (!started.isCompleted) started.complete();
    await gate.future;
    return mergeDuplicateSources(
      sources: sources,
      preferredUrl: preferredUrl,
      idle: () => true,
      merge: (from, into) async {
        await dao.deleteByUrls(from);
        return from;
      },
    );
  }
}

BookSource _source(String url, {int order = 0}) => BookSource(
  bookSourceUrl: url,
  bookSourceName: url,
  searchUrl: '/s?q={{key}}',
  customOrder: order,
);

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: '等不到');
}

void main() {
  late AppDatabase db;
  late _GatedDao dao;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = _GatedDao(db);
    GetIt.instance.registerSingleton<BookSourceDao>(dao);
    GetIt.instance.registerLazySingleton<CheckSourceService>(
      CheckSourceService.new,
    );
    await dao.upsertAll([
      _source('https://a.example', order: 0),
      _source('https://b.example', order: 1),
      _source('https://c.example', order: 2),
    ]);
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  Future<SourceManagerProvider> loaded({
    SourceImportService? importService,
    Future<int> Function(List<BookSource> sources, {String? preferredUrl})?
    mergeDuplicates,
  }) async {
    final provider = SourceManagerProvider(
      entrance: Future<void>.value(),
      importService: importService,
      mergeDuplicates: mergeDuplicates,
    );
    addTearDown(provider.dispose);
    await _until(() => !provider.isLoading && provider.totalSourceCount > 0);
    return provider;
  }

  test('an import keeps the list busy even when a background reload '
      'finishes meanwhile', () async {
    final importer = _GatedImport(dao);
    final provider = await loaded(importService: importer);

    final importing = provider.importSources([_source('https://new.example')]);
    expect(provider.isLoading, isTrue);
    expect(provider.isMutationBusy, isTrue);

    // 校驗做完、同步套用這類背景重讀，在匯入寫進去之前讀完。
    await provider.loadSources(showLoading: false);
    expect(provider.isLoading, isTrue);
    expect(provider.isMutationBusy, isTrue);

    importer.gate.complete();
    expect(await importing, (imported: 1, merged: 0));
    expect(provider.isLoading, isFalse);
    expect(provider.isMutationBusy, isFalse);
    expect(provider.totalSourceCount, 4);
  });

  test('first open with duplicates stays loading until the merged list '
      'is out', () async {
    await dao.upsert(_source('https://a.example#copy', order: 3));
    final merge = _GatedMerge(dao);
    final provider = SourceManagerProvider(
      entrance: Future<void>.value(),
      mergeDuplicates: merge.call,
    );
    addTearDown(provider.dispose);

    await merge.started.future;
    expect(provider.isLoading, isTrue);
    expect(provider.totalSourceCount, 0);

    merge.gate.complete();
    await _until(() => !provider.isLoading);
    expect(provider.totalSourceCount, 3);
    expect(provider.lastMergedDuplicates, 1);
    expect(provider.isMutationBusy, isFalse);
  });

  test('a batch job keeps the list and every row locked through its reload, '
      'then lets go', () async {
    final provider = await loaded();
    provider.toggleSelect('https://a.example');

    dao.hold = true;
    final deleting = provider.deleteSelected();
    await _until(() => dao.held.length == 1);
    expect(provider.isMutationBusy, isTrue);
    expect(provider.isSourceLocked('https://b.example'), isTrue);
    expect(provider.canReorder, isFalse);
    // 還沒讀完：清單照舊，不畫骨架。
    expect(provider.totalSourceCount, 3);

    dao.hold = false;
    dao.held.single.complete();
    await deleting;
    expect(provider.totalSourceCount, 2);
    expect(provider.isMutationBusy, isFalse);
    expect(provider.isSourceLocked('https://b.example'), isFalse);
    expect(provider.canReorder, isTrue);
  });

  test('a batch job whose reload is overtaken by a background reload keeps '
      'the list busy until the newer reload is out', () async {
    final provider = await loaded();
    provider.toggleSelect('https://a.example');

    dao.hold = true;
    final deleting = provider.deleteSelected();
    await _until(() => dao.held.length == 1);
    // 校驗做完、同步套用這類背景重讀，蓋過批次作業自己的重讀。
    final background = provider.loadSources(showLoading: false);
    await _until(() => dao.held.length == 2);

    dao.held[0].complete();
    await deleting;
    expect(provider.isMutationBusy, isTrue);
    expect(provider.canReorder, isFalse);

    dao.held[1].complete();
    await background;
    expect(provider.totalSourceCount, 2);
    expect(provider.isMutationBusy, isFalse);
  });

  test('an import whose reload is overtaken by a background reload keeps the '
      'list busy until the newer reload is out', () async {
    // 只寫進去、不另外讀清單的匯入：卡住的讀都是書源管理自己的。
    final importer = _GatedImport(dao, mergeSkipped: true)..gate.complete();
    final provider = await loaded(importService: importer);

    dao.hold = true;
    final importing = provider.importSources([_source('https://new.example')]);
    await _until(() => dao.held.length == 1);
    final background = provider.loadSources(showLoading: false);
    await _until(() => dao.held.length == 2);

    dao.held[0].complete();
    await importing;
    expect(provider.isMutationBusy, isTrue);

    dao.held[1].complete();
    await background;
    expect(provider.totalSourceCount, 4);
    expect(provider.isMutationBusy, isFalse);
  });

  test('an import whose own merge was skipped merges in its reload', () async {
    final merge = _GatedMerge(dao)..gate.complete();
    final importer = _GatedImport(dao, mergeSkipped: true)..gate.complete();
    final provider = await loaded(
      importService: importer,
      mergeDuplicates: merge.call,
    );

    await provider.importSources([_source('https://a.example#copy')]);
    expect(provider.totalSourceCount, 3);
    expect(await dao.getByUrl('https://a.example#copy'), isNull);
  });

  test('a reload after the first load keeps the list and locks the list '
      'actions; the rows look usable but changing one is refused', () async {
    final provider = await loaded();

    dao.gate = Completer<void>();
    final reload = provider.loadSources();
    expect(provider.isLoading, isTrue);
    expect(provider.isMutationBusy, isTrue);
    expect(provider.isSourceLocked('https://a.example'), isFalse);
    expect(provider.totalSourceCount, 3);

    final source = provider.allSources.first;
    await provider.toggleEnabled(source);
    expect((await dao.getByUrl(source.bookSourceUrl))!.enabled, isTrue);

    dao.gate!.complete();
    await reload;
    expect(provider.isLoading, isFalse);
    expect(provider.isMutationBusy, isFalse);
  });

  test('while a background reload merges duplicates, list actions are '
      'refused and the rows look usable', () async {
    final merge = _GatedMerge(dao);
    final provider = await loaded(mergeDuplicates: merge.call);
    await dao.upsert(_source('https://a.example#copy', order: 3));

    final reload = provider.loadSources(showLoading: false);
    await merge.started.future;
    expect(provider.isLoading, isFalse);
    expect(provider.isMutationBusy, isTrue);
    expect(provider.isSourceLocked('https://b.example'), isFalse);

    await provider.deleteSourcesByUrls(['https://c.example']);
    expect(await dao.getByUrl('https://c.example'), isNotNull);
    // 預覽面板開著時才忙起來的：說書源管理在忙，不是「未匯入有效書源」。
    Object? refused;
    try {
      await provider.importSources([_source('https://new.example')]);
    } catch (error) {
      refused = error;
    }
    expect(refused, isNotNull);
    expect(userErrorReason(refused!), '書源管理正在改書源，等它做完再匯入');
    expect(await dao.getByUrl('https://new.example'), isNull);

    merge.gate.complete();
    await reload;
    expect(provider.totalSourceCount, 3);
    expect(provider.isMutationBusy, isFalse);
  });

  test('while duplicates merge, changing one of them is refused like any '
      'other change to the sources', () async {
    final merge = _GatedMerge(dao);
    final provider = await loaded(mergeDuplicates: merge.call);
    await dao.upsert(_source('https://a.example#copy', order: 3));

    final reload = provider.loadSources(showLoading: false);
    await merge.started.future;
    // 刪掉要留下的那個：重複的那幾個的書會搬到已經刪掉的書源。
    final first = provider.allSources.first;
    unawaited(provider.toggleEnabled(first));
    unawaited(provider.deleteSource(first));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(await dao.getByUrl('https://a.example'), isNotNull);
    expect((await dao.getByUrl('https://a.example'))!.enabled, isTrue);

    merge.gate.complete();
    await reload;
    expect(provider.totalSourceCount, 3);
  });

  // 合併在等下載收尾時打開編輯：等它併完再讀，被併掉的不開——開了存的
  // 修改會寫回已經併掉的書源，下次合併又隨它刪掉。
  test('opening a source to edit while duplicates merge waits for the merge, '
      'and one merged away does not open', () async {
    final merge = _GatedMerge(dao);
    final provider = await loaded(mergeDuplicates: merge.call);
    await dao.upsert(_source('https://a.example#copy', order: 3));

    final reload = provider.loadSources(showLoading: false);
    await merge.started.future;
    BookSource? opened = _source('沒有傳回');
    var answered = false;
    unawaited(
      provider.beginEditing('https://a.example#copy').then((source) {
        opened = source;
        answered = true;
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(answered, isFalse, reason: '等合併');

    merge.gate.complete();
    await reload;
    await _until(() => answered);
    expect(opened, isNull);
    expect(await dao.getByUrl('https://a.example#copy'), isNull);
  });

  // 編輯頁開著時不併：存的時候它還在；關掉後照常併。
  test('while a source is open in the editor, duplicates wait until it '
      'closes', () async {
    final merge = _GatedMerge(dao)..gate.complete();
    final provider = await loaded(mergeDuplicates: merge.call);
    await dao.upsert(_source('https://a.example#copy', order: 3));

    final opened = await provider.beginEditing('https://a.example#copy');
    expect(opened?.bookSourceUrl, 'https://a.example#copy');
    await provider.loadSources(showLoading: false);
    expect(merge.calls, 0);
    expect(await dao.getByUrl('https://a.example#copy'), isNotNull);

    await provider.endEditing('https://a.example#copy', changed: false);
    expect(merge.calls, 1);
    expect(await dao.getByUrl('https://a.example#copy'), isNull);
    expect(provider.totalSourceCount, 3);
  });

  test('a reload that starts while duplicates merge waits for the merge '
      'and shows the merged list', () async {
    await dao.upsert(_source('https://a.example#copy', order: 3));
    final merge = _GatedMerge(dao);
    final provider = SourceManagerProvider(
      entrance: Future<void>.value(),
      mergeDuplicates: merge.call,
    );
    addTearDown(provider.dispose);
    await merge.started.future;

    // 校驗做完、同步套用這類背景重讀，正好在第一次讀清單併重複書源時開始。
    dao.hold = true;
    final reload = provider.loadSources(showLoading: false);
    await _until(() => dao.held.length == 1);
    // 讀到的是併之前的清單，回來時還在併。
    dao.hold = false;
    dao.held.single.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(provider.isLoading, isTrue);

    merge.gate.complete();
    await reload;
    await _until(() => !provider.isLoading);
    expect(provider.totalSourceCount, 3);
    expect(
      provider.allSources.map((s) => s.bookSourceUrl),
      isNot(contains('https://a.example#copy')),
    );
    expect(merge.calls, 1);
  });

  test('a reload that waited for a merge also merges duplicates that came '
      'in meanwhile', () async {
    await dao.upsert(_source('https://a.example#copy', order: 3));
    final merge = _GatedMerge(dao);
    final provider = SourceManagerProvider(
      entrance: Future<void>.value(),
      mergeDuplicates: merge.call,
    );
    addTearDown(provider.dispose);
    await merge.started.future;

    // 併網站甲的時候，同步又帶進網站乙的重複書源、重讀。
    await dao.upsert(_source('https://b.example#copy', order: 4));
    final reload = provider.loadSources(showLoading: false);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    merge.gate.complete();
    await reload;
    await _until(() => !provider.isLoading);
    expect(provider.totalSourceCount, 3);
    expect(await dao.getByUrl('https://b.example#copy'), isNull);
  });

  test(
    'a list read while a merge ran but returned after it is not shown',
    () async {
      final merge = _GatedMerge(dao);
      final provider = await loaded(mergeDuplicates: merge.call);
      await dao.upsert(_source('https://a.example#copy', order: 3));

      final merging = provider.loadSources(showLoading: false);
      await merge.started.future;
      // 併的途中讀到併之前的清單，併完才回來。
      dao.hold = true;
      final reload = provider.loadSources(showLoading: false);
      await _until(() => dao.held.length == 1);
      dao.hold = false;
      merge.gate.complete();
      await merging;
      dao.held.single.complete();
      await reload;

      expect(provider.totalSourceCount, 3);
      expect(
        provider.allSources.map((s) => s.bookSourceUrl),
        isNot(contains('https://a.example#copy')),
      );
    },
  );
}
