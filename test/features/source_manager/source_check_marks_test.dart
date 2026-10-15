import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late BookSourceDao dao;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = BookSourceDao(db);
    GetIt.instance.registerSingleton<BookSourceDao>(dao);
    GetIt.instance.registerLazySingleton<CheckSourceService>(
      CheckSourceService.new,
    );

    await dao.upsertAll([
      BookSource(
        bookSourceUrl: 'https://quarantined.example',
        bookSourceName: '隔離書源',
        bookSourceGroup:
            '精選,$abnormalSourceGroupTag,$quarantineSourceGroupTag,$timeoutSourceGroupTag',
        bookSourceComment: '// Error: 校驗超時或來源響應過慢\n\n作者的說明',
      ),
      BookSource(
        bookSourceUrl: 'https://login.example',
        bookSourceName: '登入書源',
        bookSourceGroup: '$abnormalSourceGroupTag,$loginRequiredSourceGroupTag',
        bookSourceComment: '// Error: 正文需要登入後閱讀',
      ),
      BookSource(
        bookSourceUrl: 'https://clean.example',
        bookSourceName: '正常書源',
        bookSourceGroup: '精選',
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  Future<SourceManagerProvider> loadedProvider() async {
    final provider = SourceManagerProvider(entrance: Future<void>.value());
    addTearDown(provider.dispose);
    while (provider.isLoading || provider.totalSourceCount == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return provider;
  }

  test('counts as loading while the page is still sliding in', () async {
    final entrance = Completer<void>();
    final provider = SourceManagerProvider(entrance: entrance.future);
    addTearDown(provider.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // 還沒讀書源：不能當成「尚未加入書源」。
    expect(provider.isLoading, isTrue);

    entrance.complete();
    while (provider.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(provider.totalSourceCount, 3);
  });

  test(
    'clearing every mark restores marked sources and keeps user data',
    () async {
      final provider = await loadedProvider();

      expect(await provider.clearCheckMarks(), 2);

      final quarantined = (await dao.getByUrl('https://quarantined.example'))!;
      expect(quarantined.groupTags, {'精選'});
      expect(quarantined.bookSourceComment, '作者的說明');
      expect(quarantined.isSearchEnabledByRuntime, isTrue);
      expect(quarantined.isReadingEnabledByRuntime, isTrue);

      final login = (await dao.getByUrl('https://login.example'))!;
      expect(login.bookSourceGroup, isNull);
      expect(login.isCleanupCandidate, isFalse);

      expect(provider.allGroups, ['精選']);
    },
  );

  test('clearing the selected sources leaves the others marked', () async {
    final provider = await loadedProvider();

    expect(await provider.clearCheckMarks({'https://login.example'}), 1);

    final login = (await dao.getByUrl('https://login.example'))!;
    expect(login.bookSourceGroup, isNull);
    final quarantined = (await dao.getByUrl('https://quarantined.example'))!;
    expect(quarantined.isQuarantined, isTrue);
  });

  test(
    'closing the source manager leaves the shared check service alive',
    () async {
      final first = SourceManagerProvider(entrance: Future<void>.value());
      final service = first.checkService;
      first.dispose();

      final second = SourceManagerProvider(entrance: Future<void>.value());
      addTearDown(second.dispose);

      expect(second.checkService, same(service));
      expect(service.isChecking, isFalse);
    },
  );

  test(
    'error lines go even when the comment uses single line breaks',
    () async {
      await dao.upsertAll([
        BookSource(
          bookSourceUrl: 'https://error-first.example',
          bookSourceName: '錯誤在前',
          bookSourceComment: '// Error: 舊錯誤\n作者說明',
        ),
        BookSource(
          bookSourceUrl: 'https://error-last.example',
          bookSourceName: '錯誤在後',
          bookSourceComment: '作者說明\n// Error: 舊錯誤',
        ),
      ]);
      final provider = await loadedProvider();

      await provider.clearCheckMarks({
        'https://error-first.example',
        'https://error-last.example',
      });

      expect(
        (await dao.getByUrl('https://error-first.example'))!.bookSourceComment,
        '作者說明',
      );
      expect(
        (await dao.getByUrl('https://error-last.example'))!.bookSourceComment,
        '作者說明',
      );
    },
  );

  test(
    'a background reload that overtakes the first load finishes it',
    () async {
      final gated = _GatedSourceDao(db)..gate = Completer<void>();
      GetIt.instance.unregister<BookSourceDao>();
      GetIt.instance.registerSingleton<BookSourceDao>(gated);

      final provider = SourceManagerProvider(entrance: Future<void>.value());
      addTearDown(provider.dispose);
      final countsSeen = <int>[];
      provider.addListener(() => countsSeen.add(provider.totalSourceCount));
      // 進場（這裡已經完成）之後才開始初次載入。
      await Future<void>.delayed(Duration.zero);
      expect(provider.isLoading, isTrue);

      // 校驗結束時在背景重新讀取，蓋過還沒讀完的初次載入。
      final reload = provider.loadSources(showLoading: false);
      gated.gate!.complete();
      await reload;

      expect(provider.isLoading, isFalse);
      expect(provider.isMutationBusy, isFalse);
      expect(countsSeen.last, 3);
    },
  );
}

class _GatedSourceDao extends BookSourceDao {
  _GatedSourceDao(super.db);

  Completer<void>? gate;

  @override
  Future<List<BookSource>> getAllPart() async {
    await gate?.future;
    return super.getAllPart();
  }
}
