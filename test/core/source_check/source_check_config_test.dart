import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';

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

  test('調高每段時限時，整個書源的時限跟著變長，不再卡在 120 秒', () {
    // 每段各自等 20 秒，整個書源是段數乘上每段時限；以前另外卡 120 秒，
    // 把時限從 21 調到 120 秒，總時限一直是 120 秒，調高沒有用。
    const config = SourceCheckConfig(
      keyword: '我的',
      timeoutSeconds: 21,
      checkSearch: true,
      checkDiscovery: true,
      checkInfo: true,
      checkCategory: true,
      checkContent: true,
    );
    expect(config.sourceTimeoutDuration, const Duration(seconds: 126));
  });
}
