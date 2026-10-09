import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/tts_service.dart';

/// 語速遷移契約：舊版存的是 flutter_tts 刻度（0.5 = 正常），升級後
/// 換算成使用者倍速，實際朗讀速度不得改變。
void main() {
  test('legacy flutter_tts rate converts to the same actual speed', () {
    expect(TTSService.resolveStoredRate(legacyRate: 0.5), 1.0);
    expect(TTSService.resolveStoredRate(legacyRate: 1.0), 2.0);
    expect(TTSService.resolveStoredRate(legacyRate: 0.6), closeTo(1.2, 1e-9));
  });

  test('every legacy value stays inside the new range', () {
    // 舊設定頁 0.1～1.0、舊閱讀器面板 0.5～1.5。
    for (final legacy in [0.1, 0.5, 1.0, 1.5]) {
      final rate = TTSService.resolveStoredRate(legacyRate: legacy)!;
      expect(rate, inInclusiveRange(TTSService.minRate, TTSService.maxRate));
    }
  });

  test('the new multiplier key wins over legacy keys', () {
    expect(TTSService.resolveStoredRate(multiplier: 1.3, legacyRate: 1.0), 1.3);
    expect(TTSService.resolveStoredRate(), isNull);
  });
}
