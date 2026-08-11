import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/services/cookie_store.dart';

void main() {
  final store = CookieStore();

  setUp(() async {
    await GetIt.instance.reset();
    await store.clearAll();
  });

  tearDown(() async {
    await store.clearAll();
    await GetIt.instance.reset();
  });

  test('cookie parser preserves an explicit empty value', () {
    expect(store.cookieToMap('session=; theme=dark'), <String, String>{
      'session': '',
      'theme': 'dark',
    });
  });

  test(
    'replacing with an empty value clears the previous cookie value',
    () async {
      const url = 'https://reader.example.com/book';
      await store.setCookie(url, 'session=old; theme=dark');

      await store.replaceCookie(url, 'session=');

      expect(store.cookieToMap(await store.getCookie(url)), <String, String>{
        'session': '',
        'theme': 'dark',
      });
    },
  );
}
