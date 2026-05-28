import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/services/check_source_service.dart';
import 'package:reader/core/services/event_bus.dart';

class _FakeBookSourceDao extends Fake implements BookSourceDao {}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('loadConfig reads persisted validation preferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'checkSourceKeyword': '測試詞',
      'checkSourceTimeout': 9,
      'checkSourceSearch': false,
      'checkSourceDiscovery': true,
      'checkSourceInfo': true,
      'checkSourceCategory': false,
      'checkSourceContent': false,
    });

    final service = CheckSourceService(
      sourceDao: _FakeBookSourceDao(),
      eventBus: AppEventBus(),
    );

    await service.loadConfig();

    expect(service.config.keyword, '測試詞');
    expect(service.config.timeoutSeconds, 9);
    expect(service.config.checkSearch, isFalse);
    expect(service.config.checkDiscovery, isTrue);
    expect(service.config.checkInfo, isTrue);
    expect(service.config.checkCategory, isFalse);
    expect(service.config.checkContent, isFalse);
  });

  test('source timeout budget scales with enabled checks and caps at 90s', () {
    expect(
      SourceCheckConfig.defaults.sourceTimeoutDuration,
      const Duration(seconds: 90),
    );
    expect(
      SourceCheckConfig.defaults
          .copyWith(
            timeoutSeconds: 10,
            checkDiscovery: false,
            checkInfo: false,
            checkCategory: false,
            checkContent: false,
          )
          .normalized()
          .sourceTimeoutDuration,
      const Duration(seconds: 20),
    );
  });
}
