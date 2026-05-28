import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/services/update_ignore_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('isIgnored returns false on empty store', () async {
    final store = UpdateIgnoreStore();
    expect(await store.isIgnored('v0.2.72'), isFalse);
  });

  test('ignore makes the exact same version ignored', () async {
    final store = UpdateIgnoreStore();
    await store.ignore('v0.2.72');
    expect(await store.isIgnored('v0.2.72'), isTrue);
    expect(await store.isIgnored('v0.2.73'), isFalse);
  });

  test('ignore overwrites previous version', () async {
    final store = UpdateIgnoreStore();
    await store.ignore('v0.2.72');
    await store.ignore('v0.2.73');
    expect(await store.isIgnored('v0.2.72'), isFalse);
    expect(await store.isIgnored('v0.2.73'), isTrue);
  });

  test('clear removes the ignored version', () async {
    final store = UpdateIgnoreStore();
    await store.ignore('v0.2.72');
    await store.clear();
    expect(await store.isIgnored('v0.2.72'), isFalse);
  });
}
