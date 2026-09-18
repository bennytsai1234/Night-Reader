import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/tts_service.dart';

void main() {
  group('TTS 音色可用性過濾', () {
    test('排除需要網路的音色', () {
      expect(
        TTSService.isUsableVoice({
          'name': 'network voice',
          'locale': 'zh-TW',
          'network_required': '1',
          'features': '',
        }),
        isFalse,
      );
    });

    test('排除尚未安裝的音色', () {
      expect(
        TTSService.isUsableVoice({
          'name': 'downloadable voice',
          'locale': 'zh-TW',
          'network_required': '0',
          'features': 'notInstalled',
        }),
        isFalse,
      );
    });

    test('保留已安裝的離線音色', () {
      expect(
        TTSService.isUsableVoice({
          'name': 'local voice',
          'locale': 'zh-TW',
          'network_required': '0',
          'features': 'embeddedTts',
        }),
        isTrue,
      );
    });
  });

  group('TTS 音色語言過濾', () {
    test('zh-TW 會接受同語言家族的 zh-CN 音色', () {
      expect(
        TTSService.voiceMatchesLanguage({'locale': 'zh-CN'}, 'zh-TW'),
        isTrue,
      );
    });

    test('不同語言的音色不列入目前語言', () {
      expect(
        TTSService.voiceMatchesLanguage({'locale': 'en-US'}, 'zh-TW'),
        isFalse,
      );
    });
  });
}
