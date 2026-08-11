import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/audio_handler.dart';

void main() {
  test('無效封面 URI 不會中斷通知欄媒體資訊更新', () {
    final handler = ReaderAudioHandler();

    expect(
      () => handler.updateMetadata(
        title: '測試書',
        author: '作者',
        artUri: 'http://[::1',
      ),
      returnsNormally,
    );
    expect(handler.mediaItem.value?.title, '測試書');
    expect(handler.mediaItem.value?.artUri, isNull);
  });

  test('封面 URI 會先去除前後空白', () {
    final handler = ReaderAudioHandler();

    handler.updateMetadata(
      title: '測試書',
      author: '作者',
      artUri: '  https://example.com/cover.jpg  ',
    );

    expect(
      handler.mediaItem.value?.artUri,
      Uri.parse('https://example.com/cover.jpg'),
    );
  });
}
