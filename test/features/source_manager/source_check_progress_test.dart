import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';
import 'package:night_reader/core/source_check/source_check_isolate.dart';
import 'package:night_reader/core/background_work/paused_work_file.dart';
import 'package:night_reader/features/source_manager/source_check_job.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:night_reader/features/source_manager/widgets/source_check_status_bar.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 校驗出搜尋失效：和真的校驗一樣，結果的書源帶著校驗標記與錯誤註解。
Future<SourceCheckIsolateHandle> _searchBroken(
  BookSource source,
  IsolateCheckConfig config,
  Duration timeout,
) async {
  const message = '搜尋連結規則為空';
  final checked = BookSource.fromJson(source.toJson())
    ..removeInvalidGroups()
    ..removeErrorComment()
    ..addHealthGroups(
      const SourceRuntimeHealth(
        category: SourceHealthCategory.searchBroken,
        label: searchBrokenSourceGroupTag,
        description: '搜尋規則已失效',
        allowsSearch: false,
        allowsReading: true,
        cleanupCandidate: false,
        quarantined: false,
      ),
    )
    ..addErrorComment(message);
  return SourceCheckIsolateHandle(
    result: Future.value(
      SourceCheckIsolateResult(
        stage: 'search',
        message: message,
        isHealthy: false,
        updatedSourceJson: checked.toJson(),
        logs: const [],
      ),
    ),
    abort: () {},
  );
}

/// 讀書源先出錯 [failures] 次（例如資料庫忙），之後照常。
class _FlakyDao extends BookSourceDao {
  _FlakyDao(super.db, this.failures);
  int failures;
  int reads = 0;

  @override
  Future<BookSource?> getByUrl(String url) async {
    reads++;
    if (failures-- > 0) throw StateError('資料庫讀不到');
    return super.getByUrl(url);
  }
}

/// 存在記憶體裡的暫停存檔。
class _MemoryFile extends PausedWorkFile {
  _MemoryFile() : super('check_sources');
  bool closed = false;

  @override
  bool get isClosed => closed;

  @override
  Future<String?> read() async => null;

  @override
  void saveLater(String Function() encode) {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async => closed = true;
}

/// 書源列的校驗結果與「沒有異常」篩選要對得上：校驗之後書源被別處改寫
/// （AI 修好存檔、清除校驗標記），列上不能再顯示那次校驗的結果。
void main() {
  const url = 'https://broken.example';
  late AppDatabase db;
  late BookSourceDao dao;
  late CheckSourceService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = BookSourceDao(db);
    GetIt.instance.registerSingleton<BookSourceDao>(dao);
    service = CheckSourceService(spawn: _searchBroken);
    GetIt.instance.registerSingleton<CheckSourceService>(service);
    await dao.upsert(
      BookSource(
        bookSourceUrl: url,
        bookSourceName: '壞掉的書源',
        bookSourceGroup: '精選',
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  Future<SourceManagerProvider> checkedProvider() async {
    final provider = SourceManagerProvider(entrance: Future<void>.value());
    addTearDown(provider.dispose);
    while (provider.isLoading || provider.totalSourceCount == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await service.check([url]);
    // 校驗做完、清單照資料庫重讀之後。
    while (!provider.allSources.single.hasGroupTag(abnormalSourceGroupTag)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return provider;
  }

  test('checked and left alone, the row keeps the result', () async {
    final provider = await checkedProvider();
    await provider.loadSources(showLoading: false);

    final progress = service.progressOf(url);
    expect(progress?.hasIssue, isTrue);
    expect(progress?.message, startsWith(searchBrokenSourceGroupTag));
  });

  test('rewritten as healthy after the check (an AI fix saved), the row '
      'drops the stale result and shows under no-abnormal', () async {
    final provider = await checkedProvider();

    final fixed = (await dao.getByUrl(url))!
      ..removeInvalidGroups()
      ..removeErrorComment();
    await dao.upsert(fixed);
    await provider.loadSources(showLoading: false);

    expect(service.progressOf(url), isNull);
    provider.setFilterGroup(SourceManagerProvider.noAbnormalFilter);
    expect(provider.sources.map((s) => s.bookSourceUrl), [url]);
  });

  Future<SourceManagerProvider> providerWith(CheckSourceService check) async {
    await GetIt.instance.unregister<CheckSourceService>();
    GetIt.instance.registerSingleton<CheckSourceService>(check);
    final provider = SourceManagerProvider(entrance: Future<void>.value());
    addTearDown(provider.dispose);
    while (provider.isLoading || provider.totalSourceCount == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return provider;
  }

  test('checked fine and left alone, the row keeps 校驗成功', () async {
    final healthy = CheckSourceService(
      spawn: (source, config, timeout) async => SourceCheckIsolateHandle(
        result: Future.value(
          SourceCheckIsolateResult(
            stage: 'done',
            message: '校驗成功',
            isHealthy: true,
            updatedSourceJson: source.toJson(),
            logs: const [],
          ),
        ),
        abort: () {},
      ),
    );
    final provider = await providerWith(healthy);

    await healthy.check([url]);
    await provider.loadSources(showLoading: false);

    expect(healthy.progressOf(url)?.message, '校驗成功');
    expect(healthy.progressOf(url)?.hasIssue, isFalse);
  });

  test('a check stopped midway keeps the finished rows, even while the '
      'stop is still writing, and leaves no row spinning', () async {
    const slow = 'https://slow.example';
    await dao.upsert(BookSource(bookSourceUrl: slow, bookSourceName: '慢的'));
    // 跑著的書源停下要一點時間：按了停止，這一輪還沒做完。
    final stopped = Completer<void>();
    final stopping = CheckSourceService(
      spawn: (source, config, timeout) async {
        if (source.bookSourceUrl != slow) {
          return _searchBroken(source, config, timeout);
        }
        final result = Completer<SourceCheckIsolateResult?>();
        return SourceCheckIsolateHandle(
          result: result.future,
          abort: () => stopped.future.then((_) => result.complete(null)),
        );
      },
    );
    final provider = await providerWith(stopping);

    final run = stopping.check([url, slow]);
    while (stopping.progressOf(url)?.isFinal != true ||
        stopping.progressOf(slow) == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(stopping.progressOf(slow)?.isFinal, isFalse);
    stopping.cancel();
    await provider.loadSources(showLoading: false);
    expect(stopping.progressOf(url)?.hasIssue, isTrue);

    stopped.complete();
    await run;
    await provider.loadSources(showLoading: false);

    expect(stopping.progressOf(url)?.hasIssue, isTrue);
    expect(stopping.progressOf(slow), isNull);
  });

  test('marks cleared for just this source drop its result too', () async {
    final provider = await checkedProvider();

    await provider.clearCheckMarks({url});

    expect(service.progressOf(url), isNull);
  });

  test('a check that breaks midway does not block the next one', () async {
    final flaky = _FlakyDao(db, 2);
    final checker = CheckSourceService(sourceDao: flaky, spawn: _searchBroken);
    addTearDown(checker.dispose);

    // 讀書源出錯、記錄錯誤時又讀不到：這一輪丟出來。
    await expectLater(checker.check([url]), throwsA(isA<StateError>()));
    expect(checker.isChecking, isFalse);

    final reads = flaky.reads;
    await checker.check([url]);
    expect(flaky.reads, greaterThan(reads), reason: '下一輪照常校驗');
    expect(checker.finishedRunCount, 1);
  });

  testWidgets('while a paused check settles, the bar says pausing and end '
      'still works', (tester) async {
    // 按了暫停也要等 [release] 才停得下來。
    final release = Completer<void>();
    final slow = CheckSourceService(
      spawn: (source, config, timeout) async => SourceCheckIsolateHandle(
        result: release.future.then((_) => null),
        abort: () {},
      ),
    );
    final provider = await tester.runAsync(() async {
      final provider = SourceManagerProvider(
        entrance: Future<void>.value(),
        sourceCheckService: slow,
        pausedCheck: PausedSourceCheck(file: _MemoryFile.new),
      );
      while (provider.isLoading || provider.totalSourceCount == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return provider;
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: provider!,
            builder: (_, _) =>
                SourceCheckStatusBar(provider: provider, onTap: () {}),
          ),
        ),
      ),
    );
    final file = _MemoryFile();
    final running = SourceCheckJob.of(
      slow,
      SourceCheckPlan([url]),
      file: file,
    ).run();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    provider.pauseSourceCheck();
    await tester.pump();
    expect(find.textContaining('正在暫停…'), findsOneWidget);

    await tester.tap(find.text('結束'));
    await tester.pump();
    expect(find.textContaining('正在結束…'), findsOneWidget);

    release.complete();
    await tester.runAsync(() => running);
    await tester.pump();
    expect(provider.pausedCheck.isPaused, isFalse, reason: '結束蓋過暫停');
    expect(file.closed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
    slow.dispose();
  });
}
