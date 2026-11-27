import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/playback/now_playing_artwork.dart';
import 'package:night_reader/shared/widgets/book/default_book_cover.dart';

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
    Future<File> Function(String url, String? origin)? download,
    Future<Directory> Function()? directory,
  }) => NowPlayingArtwork(
    directory: directory ?? () async => dir,
    download:
        download ??
        (url, _) async {
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

  testWidgets(
    'books sharing a cover that cannot be had each get their own night sky',
    (tester) async {
      await tester.runAsync(() async {
        // 書源沒封面時常共用同一張預設圖的網址，那張載不到時每本照自己的書名畫。
        const url = 'https://x.test/nocover.jpg';
        final art = artwork();
        final rain = await fileOf(art.resolve(url, '夜雨'));
        final dawn = await fileOf(art.resolve(url, '天明'));
        // 兩本同時在換、網址還沒試過也一樣，網址只抓一次。
        const blank = 'https://x.test/blank.jpg';
        final both = await Future.wait([
          fileOf(art.resolve(blank, '星河')),
          fileOf(art.resolve(blank, '晚鐘')),
        ]);

        expect(dawn.path, isNot(rain.path));
        expect(dawn.path, (await fileOf(art.resolve(null, '天明'))).path);
        expect(both[0].path, isNot(both[1].path));
        expect(art.resolved(url, '夜雨'), rain.uri);
        expect(art.resolved(url, '天明'), dawn.uri);
        expect(downloads, [url, blank]);
      });
    },
  );

  testWidgets('two sources sharing a cover url each keep their own artwork', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const url = 'https://x.test/shared.jpg';
      final art = NowPlayingArtwork(
        directory: () async => dir,
        download: (url, origin) async {
          downloads.add('$origin $url');
          return File('${dir.path}/${origin!.split('//').last}.png')
            ..writeAsBytesSync(image);
        },
        memoryResource: (key) async => null,
      );
      final fromA = await fileOf(
        art.resolve(url, '書', origin: 'https://a.example'),
      );
      final fromB = await fileOf(
        art.resolve(url, '書', origin: 'https://b.example'),
      );

      expect(fromB.path, isNot(fromA.path));
      expect(downloads, ['https://a.example $url', 'https://b.example $url']);
      expect(art.resolved(url, '書', origin: 'https://a.example'), fromA.uri);
      expect(art.resolved(url, '書', origin: 'https://b.example'), fromB.uri);
    });
  });

  testWidgets('a cover that failed in one source is tried again in another', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const url = 'https://x.test/shared.jpg';
      final art = NowPlayingArtwork(
        directory: () async => dir,
        download: (url, origin) async {
          downloads.add('$origin $url');
          if (origin == 'https://a.example') {
            throw const SocketException('offline');
          }
          return File('${dir.path}/b.png')..writeAsBytesSync(image);
        },
        memoryResource: (key) async => null,
      );
      final fromA = await fileOf(
        art.resolve(url, '書', origin: 'https://a.example'),
      );
      final fromB = await fileOf(
        art.resolve(url, '書', origin: 'https://b.example'),
      );

      expect(downloads, ['https://a.example $url', 'https://b.example $url']);
      expect(fromB.path, isNot(fromA.path));
      expect(art.resolved(url, '書', origin: 'https://a.example'), fromA.uri);
      expect(art.resolved(url, '書', origin: 'https://b.example'), fromB.uri);
    });
  });

  testWidgets('a cover from the web comes from the cover cache', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final cached = File('${dir.path}/cached')..writeAsBytesSync(image);
      final file = await fileOf(
        artwork(download: (url, _) async => cached)
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
        artwork(download: (url, _) async => broken)
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
