import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';
import 'package:night_reader/core/source_check/source_check_isolate.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
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
}
