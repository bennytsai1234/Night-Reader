// 換頁的每一幀成本（ADR 0018）：從點下去、換頁動畫、骨架、骨架換成內容，
// 到全部停下後再一秒。`test/frame_budget/` 的換頁情境共用。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import 'app_harness.dart';
import 'frame_budget.dart';

/// 畫面上（不含被蓋住的頁面與保留著的其他分頁）還有骨架。
bool skeletonShown() => find.byType(SkeletonBox).evaluate().isNotEmpty;

/// [page] 在畫面上、所在的頁面進場播完，上面也沒有頁面蓋著或正在移走。
bool pageSettled(Finder page) {
  final elements = page.evaluate();
  if (elements.isEmpty) return false;
  final route = ModalRoute.of(elements.first);
  if (route == null) return true;
  return (route.animation?.isCompleted ?? true) &&
      (route.secondaryAnimation?.isDismissed ?? true) &&
      route.isCurrent;
}

/// 做 [action]（點一下、返回）後一幀一幀量，直到 [settled] 成立、畫面上的
/// 骨架都換成內容，再多看一秒；印出摘要並傳回每一幀的成本。[settled] 的
/// 預設是 [page] 進場播完。
Future<List<FrameCost>> measureNavigation(
  WidgetTester tester,
  String label, {
  required Future<void> Function() action,
  Finder? page,
  bool Function()? settled,
  int tailFrames = 60,
}) async {
  final done = settled ?? () => pageSettled(page!);
  await action();
  final costs = await recordFrames(
    tester,
    realAsync: true,
    until: () => done() && !skeletonShown(),
    note: () {
      final note = [if (!done()) '換頁', if (skeletonShown()) '骨架'].join('、');
      return note.isEmpty ? null : note;
    },
    tailFrames: tailFrames,
  );
  // ignore: avoid_print
  print(describeFrames(label, costs));
  expect(done(), isTrue, reason: '$label 沒有播完');
  return costs;
}

/// 返回上一頁（等同按返回鍵）。
Future<void> goBack(WidgetTester tester) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  await navigator.maybePop();
}

/// 量完拆掉 App，讓它留下的計時器（下載排程、重試）跑完，測試才能正常結束。
Future<void> tearDownApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await settle(tester, const Duration(seconds: 5));
  await tester.pump(const Duration(minutes: 1));
}

/// 兩段量測之間讓畫面停下來。
Future<void> rest(WidgetTester tester) =>
    settle(tester, const Duration(milliseconds: 1500));

const kSiteOrigin = 'https://explore.test';
const kSiteName = '夜讀書庫';

/// 一個有發現、詳情、目錄與正文規則的書源，網頁由 [installFakeSite] 從記憶體
/// 回應。測試沒有書源 isolate，規則解析在主執行緒（App 裡在書源 isolate），
/// 網頁因此保持精簡，算進主執行緒的只有一點解析。
Future<void> seedSiteSource() => getIt<BookSourceDao>().upsertAll([
  BookSource.fromJson({
    'bookSourceUrl': kSiteOrigin,
    'bookSourceName': kSiteName,
    'searchUrl': '/search?q={{key}}',
    'exploreUrl': '最新::/new\n熱門::/hot\n完本::/end',
    'ruleExplore': _bookListRule,
    'ruleSearch': _bookListRule,
    'ruleBookInfo': {
      'name': 'tag.h1@text',
      'author': 'class.author@text',
      'intro': 'class.intro@text',
      'kind': 'class.kind@text',
      'lastChapter': 'class.toc@tag.a.-1@text',
    },
    'ruleToc': {
      'chapterList': 'class.toc@tag.a',
      'chapterName': 'text',
      'chapterUrl': 'href',
    },
    'ruleContent': {'content': 'id.content@html'},
  }),
]);

const _bookListRule = {
  'bookList': 'class.item',
  'name': 'class.name@text',
  'author': 'class.author@text',
  'bookUrl': 'class.name@href',
  'intro': 'class.intro@text',
  'kind': 'class.kind@text',
  'lastChapter': 'class.last@text',
};

/// 網路回應從記憶體給，晚 [latency]（假時間，跟著 pump 前進）才到，像真的
/// 網路一樣讓畫面先跑一段。
/// 在 `tester.runAsync` 裡呼叫。
Future<void> installFakeSite({
  Duration latency = const Duration(milliseconds: 300),
}) async {
  await NetworkService().init(ephemeral: true);
  NetworkService().dio
    ..interceptors.clear()
    ..httpClientAdapter = _FakeSite(latency);
}

class _FakeSite implements HttpClientAdapter {
  _FakeSite(this.latency);

  final Duration latency;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await Future<void>.delayed(latency);
    final uri = options.uri;
    final body = uri.host == 'explore.test' ? _page(uri.path) : null;
    return ResponseBody.fromBytes(
      utf8.encode(body ?? ''),
      body == null ? 404 : 200,
      headers: {
        Headers.contentTypeHeader: ['text/html; charset=utf-8'],
      },
    );
  }

  String? _page(String path) {
    final book = RegExp(r'^/book/(\d+)/?$').firstMatch(path);
    if (book != null) return _bookPage(int.parse(book.group(1)!));
    if (RegExp(r'^/book/\d+/c\d+\.html$').hasMatch(path)) {
      return '<div id="content">${[for (final p in kParagraphs) '<p>$p</p>'].join()}</div>';
    }
    if (path.startsWith('/new') ||
        path.startsWith('/hot') ||
        path.startsWith('/end') ||
        path.startsWith('/search')) {
      return _listPage();
    }
    return null;
  }

  /// 一頁 30 本，網路小說站分類頁常見的量。
  String _listPage() => [
    for (var i = 0; i < 30; i++)
      '<div class="item"><a class="name" href="/book/$i/">${_title(i)}</a>'
          '<span class="author">作者$i</span>'
          '<span class="kind">仙俠,連載</span>'
          '<span class="last">第${300 + i}章 終章</span>'
          '<p class="intro">${kParagraphs[i % kParagraphs.length]}</p></div>',
  ].join();

  /// 詳情與目錄在同一頁，目錄 800 章。
  String _bookPage(int index) =>
      '<h1>${_title(index)}</h1><span class="author">作者$index</span>'
      '<span class="kind">仙俠,連載</span>'
      '<p class="intro">${kParagraphs.take(3).join()}</p>'
      '<div class="toc">${[for (var c = 0; c < 800; c++) '<a href="/book/$index/c$c.html">第${c + 1}章 書頁之間（$c）</a>'].join()}</div>';

  String _title(int i) => '夜讀第$i卷';

  @override
  void close({bool force = false}) {}
}
