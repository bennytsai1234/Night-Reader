import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/services/cookie_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const url = 'https://gone.example';
  // 身分剛好以被刪書源的身分＋「_」開頭的另一個書源。
  const nested = '${url}_2';
  late AppDatabase db;

  setUp(() async {
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    registerDatabase(db);
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  test('deleting a source forgets its login and variables, not the '
      "site's cookies", () async {
    final dao = getIt<BookSourceDao>();
    await dao.upsert(BookSource(bookSourceUrl: url, bookSourceName: '刪掉的'));
    await dao.upsert(BookSource(bookSourceUrl: nested, bookSourceName: '留著的'));
    final cache = CacheManager();
    await cache.put('userInfo_$url', '{"user":"讀者"}');
    await cache.put('loginHeader_$url', '{"token":"t"}');
    await cache.put('sourceVariable_$url', 'line=2');
    await cache.put('v_${url}_token', 'abc');
    await cache.put('v_${nested}_token', 'keep');
    await CookieStore().setCookie(url, 'sid=1');

    await dao.deleteByUrl(url);

    expect(await dao.getByUrl(url), isNull);
    expect(await cache.get('userInfo_$url'), isNull);
    expect(await cache.get('loginHeader_$url'), isNull);
    expect(await cache.get('sourceVariable_$url'), isNull);
    expect(await cache.get('v_${url}_token'), isNull);
    expect(await cache.get('v_${nested}_token'), 'keep');
    // 同一個網站的其他書源可能也在用。
    expect(await CookieStore().getCookie(url), 'sid=1');
  });
}
