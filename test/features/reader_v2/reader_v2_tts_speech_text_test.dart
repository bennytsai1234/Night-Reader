import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_speech_text.dart';

void main() {
  test('獨立成行的刪節號完全不送給語音引擎', () {
    for (final text in <String>[
      '......',
      '……',
      '…',
      '⋯⋯',
      '．．．',
      ' ...... \n …… ',
    ]) {
      expect(ReaderV2TtsSpeechText.prepare(text), isEmpty, reason: text);
    }
  });

  test('句中刪節號只保留一次自然停頓', () {
    expect(ReaderV2TtsSpeechText.prepare('他想了......接著說……好吧⋯⋯'), '他想了，接著說，好吧，');
    expect(ReaderV2TtsSpeechText.prepare('等等．．．再說。'), '等等，再說。');
  });

  test('一般句點、版本號和網址不變', () {
    const text = '版本 1.2.3，請到 example.com 查看。';
    expect(ReaderV2TtsSpeechText.prepare(text), text);
  });
}
