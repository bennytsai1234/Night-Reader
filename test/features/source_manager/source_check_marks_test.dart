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
    final provider = SourceManagerProvider();
    addTearDown(provider.dispose);
    while (provider.isLoading || provider.totalSourceCount == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return provider;
  }

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
      final first = SourceManagerProvider();
      final service = first.checkService;
      first.dispose();

      final second = SourceManagerProvider();
      addTearDown(second.dispose);

      expect(second.checkService, same(service));
      expect(service.isChecking, isFalse);
    },
  );
}
