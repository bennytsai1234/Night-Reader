import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/system_playback/now_playing_artwork.dart';

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  late Directory dir;
  late List<String> downloads;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('now_playing_art_');
    downloads = [];
  });

  tearDown(() => dir.deleteSync(recursive: true));

  NowPlayingArtwork artwork({Future<File> Function(String url)? download}) =>
      NowPlayingArtwork(
        directory: () async => dir,
        download:
            download ??
            (url) async {
              downloads.add(url);
              throw const SocketException('offline');
            },
        memoryResource: (key) async =>
            key == 'memory://cover' ? [1, 2, 3] : null,
      );

  Future<File> fileOf(Future<Uri> uri) async => File((await uri).toFilePath());

  testWidgets('a book without a cover gets its night sky as a PNG', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final art = artwork();
      final file = await fileOf(art.resolve(null, '夜雨'));

      expect(file.parent.path, dir.path);
      expect(file.readAsBytesSync().take(8), _pngSignature);
      // 同一本書換章時直接拿到，不再畫一次。
      expect(art.resolved(null, '夜雨'), file.uri);
      expect(art.resolved(null, '天明'), isNull);
    });
  });

  testWidgets('a cover on the phone is handed over as it is', (tester) async {
    await tester.runAsync(() async {
      final cover = File('${dir.path}/cover.jpg')..writeAsBytesSync([1, 2, 3]);

      final local = await fileOf(
        artwork().resolve('local://${cover.path}', '書'),
      );
      final file = await fileOf(artwork().resolve(cover.uri.toString(), '書'));

      expect(local.uri, cover.uri);
      expect(file.uri, cover.uri);
    });
  });

  testWidgets('a cover kept in memory is written to a file', (tester) async {
    await tester.runAsync(() async {
      final file = await fileOf(artwork().resolve('memory://cover', '書'));

      expect(file.readAsBytesSync(), [1, 2, 3]);
    });
  });

  testWidgets('a cover that cannot be had falls back to the night sky', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final art = artwork();
      final missing = await fileOf(
        art.resolve('local://${dir.path}/no.jpg', '書'),
      );
      final offline = await fileOf(art.resolve('https://x.test/c.jpg', '書'));
      // 載不到的網路封面記著，換章時不再重抓。
      await art.resolve('https://x.test/c.jpg', '書');

      expect(missing.readAsBytesSync().take(8), _pngSignature);
      expect(offline.path, missing.path);
      expect(downloads, ['https://x.test/c.jpg']);
    });
  });

  testWidgets('a cover from the web comes from the cover cache', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final cached = File('${dir.path}/cached')..writeAsBytesSync([9]);
      final file = await fileOf(
        artwork(download: (url) async => cached)
            .resolve('https://x.test/c.jpg', '書'),
      );

      expect(file.uri, cached.uri);
    });
  });
}
