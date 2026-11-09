import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/system_playback/now_playing_artwork.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  late Directory dir;
  late List<String> downloads;

  /// 一張真的圖（4×4 的 PNG）。
  late List<int> image;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    image = await DefaultBookCover.renderPng('圖', width: 4, height: 4);
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('now_playing_art_');
    downloads = [];
  });

  tearDown(() => dir.deleteSync(recursive: true));

  NowPlayingArtwork artwork({
    Future<File> Function(String url)? download,
    Future<Directory> Function()? directory,
  }) => NowPlayingArtwork(
    directory: directory ?? () async => dir,
    download:
        download ??
        (url) async {
          downloads.add(url);
          throw const SocketException('offline');
        },
    memoryResource: (key) async => key == 'memory://cover' ? image : null,
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

  testWidgets('an audiobook without a cover gets the audiobook night sky', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final art = artwork();
      final novel = await fileOf(art.resolve(null, '夜雨'));
      final audio = await fileOf(
        art.resolve(null, '夜雨', kind: BookSourceKind.audio),
      );

      expect(audio.path, isNot(novel.path));
      expect(audio.readAsBytesSync().take(8), _pngSignature);
      expect(audio.readAsBytesSync(), isNot(novel.readAsBytesSync()));
      expect(art.resolved(null, '夜雨', kind: BookSourceKind.audio), audio.uri);
    });
  });

  testWidgets('a cover on the phone is handed over as it is', (tester) async {
    await tester.runAsync(() async {
      final cover = File('${dir.path}/cover.png')..writeAsBytesSync(image);

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

      expect(file.readAsBytesSync(), image);
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
      final cached = File('${dir.path}/cached')..writeAsBytesSync(image);
      final file = await fileOf(
        artwork(download: (url) async => cached)
            .resolve('https://x.test/c.jpg', '書'),
      );

      expect(file.uri, cached.uri);
    });
  });

  testWidgets('a cover that is not an image falls back to the night sky', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // 網站回了一頁錯誤訊息當封面。
      final broken = File('${dir.path}/broken.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final file = await fileOf(
        artwork(download: (url) async => broken)
            .resolve('https://x.test/c.jpg', '書'),
      );

      expect(file.path, isNot(broken.path));
      expect(file.readAsBytesSync().take(8), _pngSignature);
    });
  });

  testWidgets('a cover that could not be written is tried again', (
    tester,
  ) async {
    await tester.runAsync(() async {
      var full = true;
      final art = artwork(
        directory: () async {
          if (full) throw const FileSystemException('No space left');
          return dir;
        },
      );

      await expectLater(
        art.resolve(null, '書'),
        throwsA(isA<FileSystemException>()),
      );
      expect(art.resolved(null, '書'), isNull);

      full = false;
      final file = await fileOf(art.resolve(null, '書'));
      expect(file.readAsBytesSync().take(8), _pngSignature);
    });
  });
}
