import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/check_source_service.dart';

void main() {
  test('the whole-source time budget counts the later chapter samples as a '
      'stage', () {
    // 2026-11-14：正文多抽中段、後段的章之後，總時限只算正文一段，40 個書源
    // 在抽後段時撞到 80 秒的總時限，判成逾時。
    const config = SourceCheckConfig(
      keyword: '我的',
      timeoutSeconds: 20,
      checkSearch: true,
      checkDiscovery: false,
      checkInfo: true,
      checkCategory: true,
      checkContent: true,
    );
    expect(config.sourceTimeoutDuration, const Duration(seconds: 100));
  });
}
