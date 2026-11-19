import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/ai_repair/ai_repair_backups.dart';
import 'package:night_reader/core/ai_repair/ai_repair_prompt.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/source_repair_batch.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/sync/source_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 改前版本放在記憶體裡（正式的寫在 App 的資料夾）。
class _Backups extends AiRepairBackups {
  final Map<String, Map<String, dynamic>> saved = {};

  @override
  Future<Map<String, dynamic>?> get(String sourceUrl) async => saved[sourceUrl];

  @override
  Future<void> remove(String sourceUrl) async => saved.remove(sourceUrl);
}

/// 書源的更新時間是規則這一版的時間：規則改了才變，標記校驗結果不算
/// （同 Legado；匯入預覽靠它分新舊）。
void main() {
  late AppDatabase db;
  late BookSourceDao dao;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    db = AppDatabase.forTesting(NativeDatabase.memory());
    registerDatabase(db);
    dao = GetIt.instance<BookSourceDao>();
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  BookSource source() => BookSource(
    bookSourceUrl: 'https://www.old.example',
    bookSourceName: '甲',
    searchUrl: 'https://www.old.example/s?q={{key}}',
    lastUpdateTime: 1000,
  );

  Future<int> storedTime() async =>
      (await dao.getByUrl('https://www.old.example'))!.lastUpdateTime;

  test('marking a site gone keeps when the rules were changed', () async {
    await dao.upsert(source());
    await markSiteGone(source(), '網域查不到');
    expect(await storedTime(), 1000);
  });

  test('marking a source the AI cannot fix keeps when the rules were '
      'changed', () async {
    await dao.upsert(source());
    await markAiUnfixable(source(), 'site_unstable');
    expect(await storedTime(), 1000);
  });

  test('moving a source to the new address of its site changes its rules', () {
    final moved = movedSource(source(), 'https://www.new.example');
    expect(moved.searchUrl, 'https://www.new.example/s?q={{key}}');
    expect(moved.lastUpdateTime, greaterThan(1000));
  });

  test('restoring the rules from before the AI changed them is a change of '
      'its own', () async {
    await dao.upsert(source()..searchUrl = 'https://www.old.example/ai');
    final backups = _Backups()
      ..saved[source().bookSourceUrl] = source().toJson();

    expect(
      await restoreAiRepair(source().bookSourceUrl, backups: backups),
      isTrue,
    );
    final restored = (await dao.getByUrl('https://www.old.example'))!;
    expect(restored.searchUrl, 'https://www.old.example/s?q={{key}}');
    expect(restored.lastUpdateTime, greaterThan(1000));
  });

  test('rules the AI hands back unchanged keep the time', () {
    final candidate = candidateFrom(source(), sourceForAi(source()));
    expect(candidate.lastUpdateTime, 1000);
  });

  test('restoring rules that are the same as now keeps the time', () async {
    await dao.upsert(source()..lastUpdateTime = 3000);
    final backups = _Backups()
      ..saved[source().bookSourceUrl] = source().toJson();

    await restoreAiRepair(source().bookSourceUrl, backups: backups);
    expect(await storedTime(), 3000);
  });

  group('rules from the other phone', () {
    Future<void> apply(BookSource remote) =>
        SourceSync(prefs: GetIt.instance<SharedPreferences>())
            .apply({remote.bookSourceUrl: SourceSync.recordOf(remote)});

    test('that changed are a new version here', () async {
      await dao.upsert(source());
      await apply(source()..searchUrl = 'https://www.old.example/new');
      expect(await storedTime(), greaterThan(1000));
    });

    test('that only carry check marks keep the time', () async {
      await dao.upsert(source());
      await apply(
        source()
          ..bookSourceGroup = abnormalSourceGroupTag
          ..addErrorComment('搜尋失敗'),
      );
      expect(await storedTime(), 1000);
    });

    test('for a source new here get a time', () async {
      await apply(source());
      expect(await storedTime(), greaterThan(0));
    });
  });
}
