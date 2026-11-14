import 'package:html/parser.dart' as html_parser;
import 'package:night_reader/core/engine/js/encode/charsets.dart';
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
///
/// 兩邊都照試抓實際發生的讀，不讀規則：送出的編碼看搜尋請求裡關鍵字被編成
/// 哪一種（規則可能用 JS 組網址、寫寬鬆的選項，引擎也可能把認不得的編碼
/// 退回 UTF-8）；宣告的編碼看那個搜尋請求跟著轉址之後最後一個回應。
String? searchCharsetFact(BookSource source, SourceProbeReport probe) {
  final keyword = _probeKeyword(probe);
  if (keyword == null) return null;
  final sent = _sentCharset(probe.requests, keyword);
  if (sent == null) return null;
  final declared = _declaredCharset(probe, sent.index);
  if (declared == null || _family(declared) == sent.charset) return null;
  return '搜尋送關鍵字的編碼和網站不同：試抓的搜尋照 ${sent.charset} 送「$keyword」，'
      '網站的搜尋頁宣告的是 $declared';
}

/// 書源除錯記下的搜尋關鍵字（「⇒開始搜尋關鍵字: 我的」）；不是從搜尋開始的
/// 試抓是 null。
String? _probeKeyword(SourceProbeReport probe) {
  for (final (_, message) in probe.logs) {
    final match = RegExp(r'開始搜尋關鍵字: (.+)$').firstMatch(message.trim());
    if (match != null) return match.group(1)!.trim();
  }
  return null;
}

/// 第一個帶著關鍵字的請求，關鍵字被編成哪一種（utf-8 或 gbk）與它在請求
/// 紀錄的位置；關鍵字是純英數、或兩種都對不上時是 null。
({String charset, int index})? _sentCharset(List<String> lines, String key) {
  final forms = {
    'utf-8': Charsets.urlEncode(key, 'utf-8'),
    'gbk': Charsets.urlEncode(key, 'gbk'),
  };
  if (forms['utf-8'] == forms['gbk']) return null;
  for (final (i, line) in lines.indexed) {
    if (line.trimLeft().startsWith('←')) continue;
    for (final MapEntry(:key, :value) in forms.entries) {
      if (line.toUpperCase().contains(value.toUpperCase())) {
        return (charset: key, index: i);
      }
    }
  }
  return null;
}

/// 從 [from] 那個請求起，跟著轉址走到底的最後一個回應宣告的編碼：回應標頭
/// 的 charset，沒有時看那一頁的 `<meta>`。
String? _declaredCharset(SourceProbeReport probe, int from) {
  String? last;
  for (final line in probe.requests.skip(from + 1)) {
    if (line.trimLeft().startsWith('←')) {
      last = line;
    } else if (!line.contains('（轉址）')) {
      break;
    }
  }
  if (last == null) return null;
  final head = last.split('：').first;
  final header = _headerCharset.firstMatch(head)?.group(1);
  if (header != null) return header.toLowerCase();
  final url = RegExp(r'←\s*(\S+)').firstMatch(last)?.group(1);
  for (final page in probe.pages) {
    final body = page.body;
    if (body == null || url == null || !page.line.contains('← $url ')) continue;
    return _metaCharset.firstMatch(body)?.group(1)?.toLowerCase();
  }
  return null;
}

/// 同一類的編碼算一樣：GB2312、GBK、GB18030 是一家，UTF8 就是 UTF-8。
String _family(String charset) => switch (charset.toLowerCase()) {
  'gb2312' || 'gbk' || 'gb18030' => 'gbk',
  'utf8' => 'utf-8',
  final other => other,
};

/// 同 AnalyzeUrl 讀回應編碼的寫法：容許空白與引號。
final RegExp _headerCharset = RegExp(
  r'''charset\s*=\s*["']?([^;\s"'，]+)''',
  caseSensitive: false,
);
final RegExp _metaCharset = RegExp(
  r'''<meta[^>]+charset\s*=\s*["']?([\w-]+)''',
  caseSensitive: false,
);

/// 開場抓到的網頁裡，連到書源以外網域的網址（圖片、連結、表單、轉址程式）
/// 照出現次數列前幾個；沒有是 null。2026-11-13 肉肉屋：目錄頁拿掉了章節
/// 連結，同一套書庫的姊妹站有完整目錄，封面圖一直放在那個網域，AI 猜了十幾
/// 種網址才想到它。同一個網站的其他開頭（電腦版 www.、手機版 m.）另外列：
/// 2026-11-13 御书屋的手機版搜尋要 48 秒，電腦版 2 秒，AI 到第 10 輪才想到。
String? otherDomainsFact(BookSource source, SourceProbeReport probe) {
  final own = NetworkUtils.getSubDomain(source.bookSourceUrl);
  final ownHost = Uri.tryParse(source.bookSourceUrl.split('#').first)?.host
      .toLowerCase();
  final counts = <String, int>{};
  final siteCounts = <String, int>{};
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
      final host = target.host.toLowerCase();
      if (host != ownHost) {
        siteCounts.update(host, (n) => n + 1, ifAbsent: () => 1);
      }
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
    // 網頁文字裡寫出來的網址也算：肉肉屋的姊妹站只出現在頁尾的「Powered by
    // 免费小说网（https://www.17ed.com）」。
    for (final element in document.querySelectorAll('script, style')) {
      element.remove();
    }
    for (final match in _textUrl.allMatches(document.body?.text ?? '')) {
      count(match.group(0), base);
    }
  }
  String listed(Map<String, int> counts) {
    final top = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return top.take(_maxDomains).map((e) => '${e.key} ${e.value}').join('、');
  }

  final lines = [
    if (counts.isNotEmpty) '開場抓到的網頁連到這些別的網域（出現次數）：${listed(counts)}',
    if (siteCounts.isNotEmpty)
      '開場抓到的網頁連到同一個網站的其他開頭（出現次數）：${listed(siteCounts)}',
  ];
  return lines.isEmpty ? null : lines.join('\n');
}

/// 寫在程式裡的完整網址（轉址程式、`uaredirect("…")` 這類）。
final RegExp _scriptUrl = RegExp(r'''["'](https?://[^"'\s<>]+)["']''');

/// 文字裡的網址：到空白、引號、括號或全形標點為止。
final RegExp _textUrl = RegExp(r'''https?://[^\s"'<>()（）、，。]+''');

const int _maxDomains = 6;
