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
    var body = options.uri.path.endsWith('/latest') ? latest : list;
    // 清單照 page／per_page 分頁，和 GitHub 一樣。
    final query = options.uri.queryParameters;
    if (body is List && query.containsKey('per_page')) {
      final perPage = int.parse(query['per_page']!);
      final page = int.parse(query['page'] ?? '1');
      body = body.skip((page - 1) * perPage).take(perPage).toList();
    }
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

    test('stable channel skips betas', () async {
      final info = await _service(api, '0.3.2').checkLatest();
      expect(info?.tagName, 'v0.3.3');
      expect(api.paths.single, endsWith('/releases'));
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

  group('checkLatest notes', () {
    Map<String, Object?> release(
      String tag,
      String body, {
      bool prerelease = true,
      bool apk = true,
    }) => {..._release(tag, prerelease: prerelease, apk: apk), 'body': body};

    final stable = release(
      'v0.3.4',
      '整理過的介紹。\n\n- 甲\n- 乙\n- 丙',
      prerelease: false,
    );
    final betas = [
      release('v0.3.4-beta.9', '- 丙', apk: false),
      release('v0.3.4-beta.7', '- 乙'),
      release('v0.3.4-beta.5', '- 甲'),
      release('v0.3.3', '- 上一版', prerelease: false),
    ];

    Future<String?> notes(
      List<Object> list,
      String current, {
      bool includeBeta = true,
    }) async => (await _service(
      _ReleaseApi(latest: stable, list: list),
      current,
    ).checkLatest(includeBeta: includeBeta))?.updateLog;

    test('joins the betas skipped since the installed one', () async {
      // beta.9 沒有 APK、裝不了，它的說明要等下一個裝得了的版本再列。
      expect(await notes(betas, '0.3.3'), '- 乙\n- 甲');
    });

    test('a release drops the lines earlier betas already delivered', () async {
      expect(
        await notes([stable, ...betas], '0.3.4-beta.5'),
        '整理過的介紹。\n\n- 乙\n- 丙',
      );
    });

    test('stable channel shows the whole release notes', () async {
      expect(
        await notes([stable, ...betas], '0.3.3', includeBeta: false),
        '整理過的介紹。\n\n- 甲\n- 乙\n- 丙',
      );
    });

    test('stable channel joins a skipped release', () async {
      expect(
        await notes(
          [
            release('v0.3.6', '- 丙', prerelease: false),
            release('v0.3.5', '- 乙', prerelease: false),
            release('v0.3.4', '- 甲', prerelease: false),
          ],
          '0.3.4',
          includeBeta: false,
        ),
        '- 丙\n- 乙',
      );
    });

    test('reads further pages until the installed cycle', () async {
      final api = _ReleaseApi(
        latest: stable,
        list: [
          for (var i = 150; i >= 1; i--) release('v0.3.5-beta.$i', '- 第$i條'),
          release('v0.3.4', '- 上一版', prerelease: false),
        ],
      );
      final log = (await _service(
        api,
        '0.3.5-beta.1',
      ).checkLatest(includeBeta: true))?.updateLog;
      expect(log, contains('- 第150條'));
      expect(log, contains('- 第2條'), reason: '跨頁的測試版也要列出');
      expect(log, isNot(contains('- 第1條')), reason: '目前版本已經收過');
      expect(api.paths, hasLength(2));
    });
  });

  group('fetchReleaseNotes', () {
    final api = _ReleaseApi(
      latest: _release('v0.3.3'),
      list: [
        _release('v0.3.5-beta.9', draft: true),
        {
          ..._release('v0.3.4-beta.4', prerelease: true, apk: false),
          'body': '- 閱讀時記住位置',
          'published_at': '2026-10-01T08:00:00Z',
        },
        _release('v0.3.4-beta.3', prerelease: true),
        {..._release('v0.3.3'), 'published_at': '2026-09-20T08:00:00Z'},
        _release('v0.3.2'),
      ],
    );

    setUp(api.paths.clear);

    test('stable channel lists releases only, newest first', () async {
      final notes = await _service(api, '0.3.3').fetchReleaseNotes();

      expect(notes.map((note) => note.versionName), ['0.3.3', '0.3.2']);
      expect(notes.map((note) => note.isCurrent), [true, false]);
      expect(notes.first.publishedAt, DateTime.utc(2026, 9, 20, 8).toLocal());
      expect(notes.last.publishedAt, isNull);
      expect(api.paths.single, endsWith('/releases'));
    });

    test('beta channel adds betas but never drafts', () async {
      final notes = await _service(
        api,
        '0.3.4-beta.4',
      ).fetchReleaseNotes(includeBeta: true);

      // 沒附 APK 的版本也列出：更新紀錄只看說明，不看能不能安裝。
      expect(notes.map((note) => note.versionName), [
        '0.3.4-beta.4',
        '0.3.4-beta.3',
        '0.3.3',
        '0.3.2',
      ]);
      expect(notes.first.isCurrent, isTrue);
      expect(releaseNotesForDisplay(notes.first.body), '• 閱讀時記住位置');
    });
  });
}
