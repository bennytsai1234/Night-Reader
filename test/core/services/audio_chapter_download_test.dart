import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/audio_chapter_download.dart';

void main() {
  test('a downloaded episode keeps the audio extension of its URL, or of '
      'the response type when the URL has none', () {
    String ext(String url, [String? type]) =>
        AudioChapterDownload.extensionFor(url, type);

    expect(ext('https://cdn.test/ep1.M4A?token=x'), '.m4a');
    expect(ext('https://cdn.test/play?id=1', 'audio/mp4; charset=x'), '.m4a');
    expect(ext('https://cdn.test/play?id=1', 'audio/ogg'), '.ogg');
    expect(ext('https://cdn.test/play.php?id=1', 'text/html'), '.mp3');
  });
}
