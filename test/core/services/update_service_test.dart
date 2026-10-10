import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/update_service.dart';

/// 依路徑回傳固定 JSON 的 HTTP 轉接器，記下請求過的路徑。
class _ReleaseApi implements HttpClientAdapter {
  _ReleaseApi({required this.latest, required this.list});

  final Object latest;
  final Object list;
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.uri.path);
    final body = options.uri.path.endsWith('/latest') ? latest : list;
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _release(
  String tag, {
  bool prerelease = false,
  bool draft = false,
  bool apk = true,
}) => {
  'tag_name': tag,
  'prerelease': prerelease,
  'draft': draft,
  'body': '',
  'html_url': 'https://github.com/x/releases/$tag',
  'assets': [
    {
      'name': apk ? 'night-reader-$tag-arm64-v8a.apk' : 'notes.txt',
      'browser_download_url': 'https://github.com/x/$tag.apk',
      'size': 10,
    },
  ],
};

AppUpdateService _service(_ReleaseApi api, String current) => AppUpdateService(
  dio: Dio()..httpClientAdapter = api,
  currentVersionLoader: () async => current,
);

void main() {
  group('ReleaseVersion', () {
    int compare(String a, String b) =>
        ReleaseVersion.tryParse(a)!.compareTo(ReleaseVersion.tryParse(b)!);

    test('orders betas before the release of the same version', () {
      expect(compare('0.3.4-beta.1', '0.3.4'), lessThan(0));
      expect(compare('v0.3.4-beta.2', '0.3.4-beta.10'), lessThan(0));
      expect(compare('0.3.4-beta.1', '0.3.3'), greaterThan(0));
      expect(compare('v0.4.0', '0.3.9-beta.7'), greaterThan(0));
      expect(compare('v0.3.3', '0.3.3'), 0);
    });

    test('rejects formats CI does not publish', () {
      expect(ReleaseVersion.tryParse('0.3'), isNull);
      expect(ReleaseVersion.tryParse('0.3.4-rc.1'), isNull);
      expect(ReleaseVersion.tryParse('0.3.4+180'), isNull);
    });
  });

  group('checkLatest', () {
    final api = _ReleaseApi(
      latest: _release('v0.3.3'),
      list: [
        _release('v0.3.5-beta.9', draft: true),
        _release('v0.3.4-beta.4', prerelease: true, apk: false),
        _release('v0.3.4-beta.3', prerelease: true),
        _release('v0.3.4-beta.2', prerelease: true),
        _release('v0.3.3'),
      ],
    );

    setUp(api.paths.clear);

    test('stable channel only asks for the latest release', () async {
      final info = await _service(api, '0.3.2').checkLatest();
      expect(info?.tagName, 'v0.3.3');
      expect(api.paths.single, endsWith('/releases/latest'));
    });

    test(
      'stable channel does not offer an older release to a beta build',
      () async {
        expect(await _service(api, '0.3.4-beta.2').checkLatest(), isNull);
      },
    );

    test(
      'beta channel picks the newest installable non-draft release',
      () async {
        final info = await _service(
          api,
          '0.3.3',
        ).checkLatest(includeBeta: true);
        expect(info?.tagName, 'v0.3.4-beta.3');
        expect(info?.versionName, '0.3.4-beta.3');
        expect(api.paths.single, endsWith('/releases'));
      },
    );

    test('beta channel reports up to date on the newest beta', () async {
      final info = await _service(
        api,
        '0.3.4-beta.3',
      ).checkLatest(includeBeta: true);
      expect(info, isNull);
    });
  });
}
