import 'package:html/parser.dart' as html_parser;
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/network/request_log.dart';

/// 抓一章正文時只抓了第一頁：第一頁（[pages] 的第 [first] 筆，回應那一行
/// 帶整頁原文）有指向同一章下一頁的連結（[isNextPageOfChapter]），之後卻
/// 沒有再送出任何請求。傳回那個連結；有接下去抓或沒有這種連結是 null。
///
/// [pages] 是抓這一章時的請求紀錄（[RequestLog.pages] 的樣子）。2026-11-12
/// 下書網的 AI 交出的規則只抓到每章的前半頁（95393.html，後半在
/// 95393_2.html），校驗照樣通過；11-13 另一次寫了 `nextContentUrl`，
/// 選擇器卻抓不到連結，同樣只有前半頁，所以看的是之後有沒有請求，不看規則
/// 有沒有寫；有請求就算接上了，不比網址（規則可能換一種寫法抓下一頁，例如
/// 網站的 API）。
///
/// 目錄上的章節 [chapters]（含下一章）不算下一頁：2026-11-13 腐文小说一頁
/// 一章，目錄的第二章就是 27752_2.html，引擎照 Legado 不把下一章當同一章的
/// 下一頁抓。正文規則自己抓網頁的（[contentRuleFetchesItself]）由呼叫的地方
/// 排除。
String? unjoinedNextPage(
  List<LoggedPage> pages,
  int first, {
  Iterable<String> chapters = const [],
}) {
  final body = pages[first].body;
  final url = _respondedUrl(pages[first].line);
  final page = url == null ? null : Uri.tryParse(url);
  if (body == null || page == null) return null;
  final listed = {
    for (final chapter in chapters)
      if (_resolve(page, _withoutOptions(chapter)) case final uri?)
        '${uri.removeFragment()}',
  };
  for (final link in html_parser.parse(body).querySelectorAll('a[href]')) {
    final href = link.attributes['href']!.trim();
    if (href.isEmpty || href.startsWith('javascript:')) continue;
    final target = _resolve(page, href);
    if (target == null || !isNextPageOfChapter(page, target)) continue;
    final next = '${target.removeFragment()}';
    if (listed.contains(next)) continue;
    final fetchedMore = pages
        .skip(first + 1)
        .any((later) => _isRequestLine(later.line));
    return fetchedMore ? null : next;
  }
  return null;
}

/// 正文規則自己抓網頁（`java.ajax` 這類）：下一頁可能由規則自己接，
/// [unjoinedNextPage] 不看。
bool contentRuleFetchesItself(BookSource source) =>
    _fetchesItself.hasMatch(source.ruleContent?.content ?? '');

final RegExp _fetchesItself = RegExp(
  r'java\.(ajax|ajaxAll|get|post|connect)\(',
);

/// [link] 是不是 [chapter] 這一章的下一頁：同一個網站，檔名是這一頁的接
/// `_2`、`-2` 這類（95393.html → 95393_2.html），或同一個路徑換了 page、p
/// 這類頁碼參數。下一章（95394.html）不算。
bool isNextPageOfChapter(Uri chapter, Uri link) {
  if (link.host != chapter.host) return false;
  final parts = RegExp(r'^(.*?)(\.[A-Za-z0-9]+)?$').firstMatch(chapter.path)!;
  final stem = RegExp.escape(parts.group(1)!);
  final extension = RegExp.escape(parts.group(2) ?? '');
  if (RegExp('^$stem[_-]\\d+$extension\$').hasMatch(link.path)) return true;
  if (link.path != chapter.path) return false;
  for (final name in const ['page', 'p', 'pn', 'pg']) {
    final next = int.tryParse(link.queryParameters[name] ?? '');
    final current = int.tryParse(chapter.queryParameters[name] ?? '1') ?? 1;
    if (next != null && next > current) return true;
  }
  return false;
}

/// 回應那一行（`  ← 網址 200 …`）的網址：轉址後實際回應的那一頁；不是
/// 回應那一行是 null。
String? _respondedUrl(String line) =>
    RegExp(r'^\s*← (\S+)').firstMatch(line)?.group(1);

/// 請求那一行（`GET` 不寫方法、其他寫在前面，轉址到的標「（轉址）」）；
/// 回應那一行（`←` 開頭）與空行不是。
bool _isRequestLine(String line) {
  final trimmed = line.trim();
  return trimmed.isNotEmpty && !trimmed.startsWith('←');
}

/// 書源網址規則的網址後面可能接著 `,{"method":"POST",…}`，只留網址。
String _withoutOptions(String url) => url.split(RegExp(r',\s*\{')).first.trim();

Uri? _resolve(Uri base, String reference) {
  try {
    return base.resolve(reference);
  } on FormatException {
    return null;
  }
}
