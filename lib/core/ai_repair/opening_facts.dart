import 'package:html/parser.dart' as html_parser;
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/utils/network_utils.dart';

import 'source_probe.dart';

/// 開場寫給 AI 的事實：程式從書源與開場試抓就讀得到、AI 卻要好幾輪才推得
/// 出來的（`agent-harness` 第 3 步）。只寫事實，不寫建議。
List<String> openingFacts(BookSource source, SourceProbeReport probe) => [
  ?searchCharsetFact(source, probe),
  ?otherDomainsFact(source, probe),
];

/// 搜尋送關鍵字的編碼和網站搜尋頁宣告的不同時的那一句；相同、讀不出來或
/// 沒有搜尋時是 null。2026-11-13 QQ文学网：書源用 GBK 送，網站改成 UTF-8
/// 後不認得關鍵字、回固定推薦書，AI 試了二十幾輪別的網址與方法才想到編碼。
String? searchCharsetFact(BookSource source, SourceProbeReport probe) {
  final searchUrl = source.searchUrl ?? '';
  if (!searchUrl.contains('key')) return null;
  final written = _optionCharset.firstMatch(searchUrl)?.group(1)?.toLowerCase();
  final sent = _family(written ?? 'utf-8');
  final declared = _declaredCharset(probe);
  if (declared == null || _family(declared) == sent) return null;
  final how = written == null ? '網址沒寫編碼，照 UTF-8' : '網址寫了 $written';
  return '搜尋送關鍵字的編碼和網站不同：書源的搜尋$how送，網站的搜尋頁宣告的是 '
      '$declared';
}

/// 試抓的第一個回應（搜尋頁）宣告的編碼：回應標頭的 charset，沒有時看網頁
/// 的 `<meta charset>`。
String? _declaredCharset(SourceProbeReport probe) {
  for (final line in probe.requests) {
    if (!line.trimLeft().startsWith('←')) continue;
    final header = _headerCharset.firstMatch(line.split('：').first)?.group(1);
    if (header != null) return header.toLowerCase();
    break;
  }
  for (final page in probe.pages) {
    if (page.body case final body?) {
      return _metaCharset.firstMatch(body)?.group(1)?.toLowerCase();
    }
  }
  return null;
}

/// 同一類的編碼算一樣：GB2312、GBK、GB18030 是一家，UTF8 就是 UTF-8。
String _family(String charset) => switch (charset.toLowerCase()) {
  'gb2312' || 'gbk' || 'gb18030' => 'gbk',
  'utf8' => 'utf-8',
  final other => other,
};

final RegExp _optionCharset = RegExp(
  r'''["']charset["']\s*:\s*["']([\w-]+)["']''',
  caseSensitive: false,
);
final RegExp _headerCharset = RegExp(r'charset=([\w-]+)', caseSensitive: false);
final RegExp _metaCharset = RegExp(
  r'''<meta[^>]+charset=["']?([\w-]+)''',
  caseSensitive: false,
);

/// 開場抓到的網頁裡，連到書源以外網域的網址（圖片、連結、表單、轉址程式）
/// 照出現次數列前幾個；沒有是 null。2026-11-13 肉肉屋：目錄頁拿掉了章節
/// 連結，同一套書庫的姊妹站有完整目錄，封面圖一直放在那個網域，AI 猜了十幾
/// 種網址才想到它。
String? otherDomainsFact(BookSource source, SourceProbeReport probe) {
  final own = NetworkUtils.getSubDomain(source.bookSourceUrl);
  final counts = <String, int>{};
  void count(String? raw, Uri base) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty || value.startsWith('#') || value.startsWith('data:')) {
      return;
    }
    final Uri target;
    try {
      target = base.resolve(value);
    } on FormatException {
      return;
    }
    if (!target.scheme.startsWith('http') || target.host.isEmpty) return;
    if (NetworkUtils.getSubDomain('${target.scheme}://${target.host}') == own) {
      return;
    }
    counts.update(target.host, (n) => n + 1, ifAbsent: () => 1);
  }

  for (final page in probe.pages) {
    final body = page.body;
    if (body == null || !body.trimLeft().startsWith('<')) continue;
    final base = Uri.tryParse(
      RegExp(r'←\s*(\S+)').firstMatch(page.line)?.group(1) ?? '',
    );
    if (base == null) continue;
    final document = html_parser.parse(body);
    for (final element in document.querySelectorAll(
      '[src], [href], [action], [data-original], [data-src]',
    )) {
      for (final name in const [
        'src',
        'href',
        'action',
        'data-original',
        'data-src',
      ]) {
        count(element.attributes[name], base);
      }
    }
    for (final script in document.querySelectorAll('script')) {
      for (final match in _scriptUrl.allMatches(script.text)) {
        count(match.group(1), base);
      }
    }
  }
  if (counts.isEmpty) return null;
  final top = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return '開場抓到的網頁連到這些別的網域（出現次數）：'
      '${top.take(_maxDomains).map((e) => '${e.key} ${e.value}').join('、')}';
}

/// 寫在程式裡的完整網址（轉址程式、`uaredirect("…")` 這類）。
final RegExp _scriptUrl = RegExp(r'''["'](https?://[^"'\s<>]+)["']''');

const int _maxDomains = 6;
