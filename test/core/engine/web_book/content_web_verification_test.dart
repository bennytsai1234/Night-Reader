import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/core/services/source_interaction.dart';

import '../../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

/// 閱讀中書源要使用者在網頁上驗證（`java.startBrowserAwait`，多半是網站刁難
/// 時才走到的備援）：立刻失敗、說清楚是要驗證，並記下要開的網頁給閱讀器的
/// 「前往驗證」（ADR 0038）。
void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();
  final skip = quickJsUnavailableReason();

  late HttpServer server;
  late String baseUrl;
  final longText = '正文的一段話，' * 60;

  // /blocked 是網站的真人驗證頁，/open 讀得到。
  setUpAll(() async {
    await NetworkService().init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      final content = request.uri.path == '/open' ? longText : 'Just a moment';
      request.response.write(
        '<html><body><div id="content">$content</div></body></html>',
      );
      await request.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  BookSource source(String contentRule) => BookSource.fromJson({
    'bookSourceName': '測試',
    'bookSourceUrl': baseUrl,
    'ruleContent': {'content': contentRule},
  });
  Book book() => Book(bookUrl: '$baseUrl/book', origin: baseUrl, name: '書');
  BookChapter chapter(String path) =>
      BookChapter(url: '$baseUrl$path', title: '第一章');

  // 照源倉庫書源的寫法：看到驗證頁就開網頁等使用者，再拿網頁內容。
  const verifyOnChallenge =
      '<js>if (result.match(/Just a moment/)) {'
      ' result = java.startBrowserAwait(baseUrl, "真人驗證").body();'
      '} result</js>id.content@text';

  setUp(() => SourceInteraction.forgetVerification(baseUrl));

  test(
    'a rule that needs the web page fails as needing verification',
    () async {
      final error = await BookSourceService()
          .getContent(source(verifyOnChallenge), book(), chapter('/blocked'))
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(error, isA<SourceVerificationException>());
      expect(
        SourceVerificationException.describes(
          (error! as SourceVerificationException).message,
        ),
        isTrue,
      );
      // 閱讀器的「前往驗證」開這一頁，帶著書源的標題。
      final remembered = SourceInteraction.verificationFor(baseUrl);
      expect(remembered?.url, '$baseUrl/blocked');
      expect(remembered?.title, '真人驗證');
    },
    skip: skip,
  );

  test('a rule that swallows the blocked call and gets nothing still fails '
      'as needing verification', () async {
    const swallowed =
        '<js>try { java.startBrowserAwait(baseUrl, "驗證"); } catch (e) {}'
        ' ""</js>';
    await expectLater(
      BookSourceService().getContent(
        source(swallowed),
        book(),
        chapter('/blocked'),
      ),
      throwsA(isA<SourceVerificationException>()),
    );
    expect(SourceInteraction.verificationFor(baseUrl), isNotNull);
  }, skip: skip);

  test('a rule that swallows the blocked call and still reads the chapter '
      'succeeds', () async {
    const fallback =
        '<js>try { java.startBrowserAwait(baseUrl, "驗證"); } catch (e) {}'
        ' result</js>id.content@text';
    expect(
      await BookSourceService().getContent(
        source(fallback),
        book(),
        chapter('/open'),
      ),
      contains('正文的一段話'),
    );
  }, skip: skip);

  test('a readable page never asks for verification', () async {
    expect(
      await BookSourceService().getContent(
        source(verifyOnChallenge),
        book(),
        chapter('/open'),
      ),
      contains('正文的一段話'),
    );
    expect(SourceInteraction.verificationFor(baseUrl), isNull);
  }, skip: skip);
}
