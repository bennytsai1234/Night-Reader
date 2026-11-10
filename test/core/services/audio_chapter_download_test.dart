import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/audio_chapter_download.dart';
import 'package:night_reader/core/services/book_chapter_files.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:path/path.dart' as p;

import '../../features/audiobook/audiobook_test_doubles.dart';

/// 每個網址回固定的內容與類型。
class _Adapter implements HttpClientAdapter {
  _Adapter(this.body, this.type);

  final List<int> body;
  final String type;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: [type],
    },
  );

  @override
  void close({bool force = false}) {}
}

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

  group('download', () {
    late Directory root;
    final source = BookSource(
      bookSourceUrl: 'https://audio.test',
      bookSourceName: '聽書',
      bookSourceType: SourceType.audio,
    );
    final book = Book(
      bookUrl: 'https://audio.test/book/1',
      origin: 'https://audio.test',
      name: '長夜將盡',
      type: SourceType.audio,
    );
    final chapter = BookChapter(
      url: 'https://audio.test/ep1',
      title: '第 1 集',
      bookUrl: book.bookUrl,
    );

    setUp(() {
      root = Directory.systemTemp.createTempSync('audio_download_');
      AppStoragePaths.useRoots((
        documents: p.join(root.path, 'docs'),
        support: p.join(root.path, 'support'),
        temporary: p.join(root.path, 'tmp'),
      ));
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<File> download(List<int> body, String type) =>
        AudioChapterDownload.download(
          source,
          book,
          chapter,
          service: FakeAudioSourceService(),
          dio: Dio()..httpClientAdapter = _Adapter(body, type),
        );

    test('an audio file is saved and counts as downloaded', () async {
      final file = await download([0x49, 0x44, 0x33, 1, 2, 3], 'audio/mpeg');
      expect(p.extension(file.path), '.mp3');
      expect(await BookChapterFiles.fileFor(book, chapter), isNotNull);
    });

    test('a stream playlist or a web page is refused and nothing is left '
        'behind to hide the online stream', () async {
      for (final (body, type) in [
        ('#EXTM3U\n#EXTINF:10,\nsegment.ts\n', 'application/vnd.apple.mpegurl'),
        ('#EXTM3U\nsegment.ts\n', 'application/octet-stream'),
        ('<html><body>請先登入</body></html>', 'text/html'),
      ]) {
        await expectLater(
          download(utf8.encode(body), type),
          throwsA(isA<AudioDownloadRefused>()),
        );
        expect(await BookChapterFiles.fileFor(book, chapter), isNull);
      }
    });
  });
}
