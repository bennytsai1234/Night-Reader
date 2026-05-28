import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:reader/core/services/cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('works without registered CacheDao', () async {
    final cache = CacheManager();
    final key = 'cache_manager_no_dao_${DateTime.now().microsecondsSinceEpoch}';

    await cache.put(key, 'content');

    expect(await cache.get(key), 'content');

    await cache.delete(key);

    expect(await cache.get(key), isNull);
  });
}
