import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/fonts/app_font.dart';
import 'package:night_reader/core/fonts/font_library.dart';

/// 選了才下載的字型（ADR 0045）：下載、核對、註冊，壞掉的檔案不留。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.bytes);

  final List<int> bytes;
  final gate = Completer<void>();
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    await gate.future;
    return ResponseBody(
      Stream.value(Uint8List.fromList(bytes)),
      200,
      headers: {
        Headers.contentLengthHeader: ['${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final good = List<int>.generate(4096, (i) => i % 251);
  late Directory dir;
  late _FakeAdapter adapter;
  late List<String> registered;

  AppFontFile spec(List<int> bytes) => AppFontFile(
    family: 'TestFamily',
    fileName: 'test.ttf',
    url: 'https://example.com/test.ttf',
    bytes: bytes.length,
    sha256: sha256.convert(bytes).toString(),
  );

  FontLibrary library({required List<int> served, AppFontFile? file}) {
    adapter = _FakeAdapter(served);
    final dio = Dio()..httpClientAdapter = adapter;
    final fontFile = file ?? spec(good);
    return FontLibrary(
      dio: dio,
      directoryLoader: () async => dir,
      register: (family, bytes) async => registered.add(family),
      fileOf: (font) => font == AppFont.system ? null : fontFile,
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fonts');
    registered = [];
  });
  tearDown(() => dir.delete(recursive: true));

  test('the system font is always usable and has no family', () async {
    final fonts = library(served: good);
    expect(await fonts.ensure(AppFont.system), isTrue);
    expect(fonts.familyOf(AppFont.system), isNull);
    expect(adapter.requests, 0);
  });

  test('a picked font downloads once, is checked, then registered', () async {
    final fonts = library(served: good);
    var changes = 0;
    fonts.changes.addListener(() => changes++);
    expect(fonts.status(AppFont.wenkaiTc).value, isA<FontMissing>());
    expect(fonts.familyOf(AppFont.wenkaiTc), isNull);

    final first = fonts.ensure(AppFont.wenkaiTc);
    final second = fonts.ensure(AppFont.wenkaiTc);
    await pumpEventQueue();
    expect(fonts.status(AppFont.wenkaiTc).value, isA<FontDownloading>());
    adapter.gate.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);

    expect(adapter.requests, 1, reason: '同時要求共用同一次下載');
    expect(registered, ['TestFamily']);
    expect(changes, 1);
    expect(fonts.status(AppFont.wenkaiTc).value, isA<FontReady>());
    expect(fonts.familyOf(AppFont.wenkaiTc), 'TestFamily');
    expect(File('${dir.path}/test.ttf').readAsBytesSync(), good);
    expect(File('${dir.path}/test.ttf.part').existsSync(), isFalse);

    expect(await fonts.ensure(AppFont.wenkaiTc), isTrue);
    expect(adapter.requests, 1);
  });

  test('a download that does not match is thrown away', () async {
    final wrong = List<int>.of(good)..[10] ^= 0xff;
    final fonts = library(served: wrong);
    adapter.gate.complete();
    expect(await fonts.ensure(AppFont.notoSerifTc), isFalse);
    expect(fonts.status(AppFont.notoSerifTc).value, isA<FontFailed>());
    expect(fonts.familyOf(AppFont.notoSerifTc), isNull);
    expect(registered, isEmpty);
    expect(dir.listSync(), isEmpty, reason: '壞掉的檔案與 .part 都不留');
  });

  test('start registers a downloaded font before returning and downloads '
      'a missing one in the background', () async {
    File('${dir.path}/test.ttf').writeAsBytesSync(good);
    final fonts = library(served: good);
    await fonts.start([AppFont.wenkaiTc, AppFont.system]);
    expect(registered, ['TestFamily']);
    expect(fonts.familyOf(AppFont.wenkaiTc), 'TestFamily');
    expect(adapter.requests, 0);

    File('${dir.path}/test.ttf').deleteSync();
    final fresh = library(served: good);
    await fresh.start([AppFont.notoSerifTc]);
    expect(fresh.familyOf(AppFont.notoSerifTc), isNull, reason: '不等下載');
    adapter.gate.complete();
    await expectLater(fresh.ensure(AppFont.notoSerifTc), completion(isTrue));
    expect(fresh.familyOf(AppFont.notoSerifTc), 'TestFamily');
  });

  test(
    'a file that cannot be registered is deleted and downloaded again',
    () async {
      File('${dir.path}/test.ttf').writeAsBytesSync(good);
      var failRegister = true;
      adapter = _FakeAdapter(good)..gate.complete();
      final fonts = FontLibrary(
        dio: Dio()..httpClientAdapter = adapter,
        directoryLoader: () async => dir,
        register: (family, bytes) async {
          if (failRegister) throw StateError('broken font');
          registered.add(family);
        },
        fileOf: (font) => font == AppFont.system ? null : spec(good),
      );
      expect(await fonts.ensure(AppFont.wenkaiTc), isFalse);
      expect(fonts.status(AppFont.wenkaiTc).value, isA<FontFailed>());
      expect(File('${dir.path}/test.ttf').existsSync(), isFalse);
      expect(adapter.requests, 0);

      failRegister = false;
      expect(await fonts.ensure(AppFont.wenkaiTc), isTrue);
      expect(adapter.requests, 1, reason: '再選一次真的重新下載');
      expect(registered, ['TestFamily']);
    },
  );

  test('opening the app clears a half-finished download', () async {
    File('${dir.path}/test.ttf.part').writeAsBytesSync([1, 2, 3]);
    final fonts = library(served: good);
    await fonts.start(const []);
    expect(File('${dir.path}/test.ttf.part').existsSync(), isFalse);
  });

  test('every font id is stable and unknown ids fall back to the system', () {
    expect(AppFont.fromStorage('wenkaiTc'), AppFont.wenkaiTc);
    expect(AppFont.fromStorage('notoSerifTc'), AppFont.notoSerifTc);
    expect(AppFont.fromStorage('gone'), AppFont.system);
    expect(AppFont.fromStorage(null), AppFont.system);
    for (final font in AppFont.values) {
      final file = font.file;
      if (file == null) continue;
      expect(file.url, startsWith('https://'));
      expect(file.sha256, hasLength(64));
      expect(file.bytes, greaterThan(1000000));
    }
  });
}
