// 書源校驗的正文抽查：抽哪幾章、章名像付費章、像下載站、兩章一半以上是
// 同一段文字。不讀校驗的狀態。
import 'dart:math' as math;

import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/chapter_content_kind.dart';

import 'source_check_verdict.dart';

bool looksLikeLockedChapter(BookChapter chapter) {
  if (chapter.isVip && !chapter.isPay) return true;
  final normalized = chapter.title.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return hasPaidMarker(normalized);
}

/// 第 1 章在前幾章裡找；比這多章的書才抽中段、後段。
const int _headProbeSpan = 5;

/// 中段、後段抽哪幾章：50%、75%、90% 的位置；章名寫了 VIP 這類字樣的
/// （書源沒標付費，只是章名這樣寫）優先，頂替後兩個位置。
List<int> laterSampleIndexes(List<BookChapter> chapters) {
  final count = chapters.length;
  if (count <= _headProbeSpan) return const [];
  int at(double share) =>
      math.max(_headProbeSpan, (count * share).floor()).clamp(0, count - 1);
  final positions = [at(0.5), at(0.75), at(0.9)];
  final titled = [
    for (var i = _headProbeSpan; i < count; i++)
      if (looksLikeLockedChapter(chapters[i])) i,
  ];
  if (titled.isNotEmpty) {
    positions[2] = titled.last;
    if (titled.length > 1) positions[1] = titled.first;
  }
  return positions.toSet().toList();
}

/// 兩段文字有一半以上（各自的字數）是同一些句子時，傳回共同的句子；
/// 是圖或音訊網址的、或沒有共同到一半的是 null。
List<String>? sharedSentences(String a, String b) {
  // 付費提示只有幾十字，類型看不出來（不到小說的字數）也要比。
  bool media(String text) => switch (ChapterContentKind.of(text)) {
    ChapterContentKind.images || ChapterContentKind.audio => true,
    _ => false,
  };
  if (media(a) || media(b)) return null;
  // 照每句出現的次數算：章內重複的台詞先去重的話，作者的話只佔一小段也會
  // 算成一半以上（Codex 審查）。
  Map<String, int> sentences(String text) {
    final counts = <String, int>{};
    for (final part in text.split(RegExp(r'[\n。！？!?；;]'))) {
      final sentence = part.trim();
      if (sentence.isNotEmpty) {
        counts.update(sentence, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  final left = sentences(a);
  final right = sentences(b);
  int length(Map<String, int> counts) => counts.entries.fold(
    0,
    (sum, entry) => sum + entry.key.length * entry.value,
  );
  final shared = [
    for (final sentence in left.keys)
      if (right.containsKey(sentence)) sentence,
  ];
  if (shared.isEmpty) return null;
  final sharedLength = shared.fold(
    0,
    (sum, sentence) =>
        sum + sentence.length * math.min(left[sentence]!, right[sentence]!),
  );
  if (sharedLength * 2 < length(left) || sharedLength * 2 < length(right)) {
    return null;
  }
  return shared;
}

/// 拿掉空白，比對開頭用。
String flatText(String text) => text.replaceAll(RegExp(r'\s+'), '');

/// 付費提示的字樣（章名與正文共用）。
const List<String> _paidMarkers = [
  '🔒',
  'vip',
  '鎖章',
  '锁章',
  '解鎖',
  '解锁',
  '付費',
  '付费',
  '收費',
  '收费',
  '訂閱',
  '订阅',
  '購買',
  '购买',
];

bool hasPaidMarker(String text) {
  final lower = text.toLowerCase();
  return _paidMarkers.any(lower.contains);
}

List<int> buildContentProbeIndexes(List<BookChapter> chapters, int maxProbe) {
  final preferred = <int>[];
  final fallback = <int>[];

  void addProbe(int index) {
    if (index < 0 || index >= chapters.length) return;
    if (preferred.contains(index) || fallback.contains(index)) return;
    if (looksLikeLockedChapter(chapters[index])) {
      fallback.add(index);
    } else {
      preferred.add(index);
    }
  }

  final headCount = math.min(maxProbe, chapters.length);
  for (var i = 0; i < headCount; i++) {
    addProbe(i);
  }

  final tailStart = math.max(chapters.length - maxProbe, 0);
  for (var i = tailStart; i < chapters.length; i++) {
    addProbe(i);
  }

  return <int>[...preferred, ...fallback].take(maxProbe).toList();
}

bool looksLikeDownloadOnly(Book book, List<BookChapter> readableChapters) {
  if (book.origin.isEmpty) return false;
  final urls = <String>[
    book.bookUrl.trim().toLowerCase(),
    book.tocUrl.trim().toLowerCase(),
    if (readableChapters.isNotEmpty)
      readableChapters.first.url.trim().toLowerCase(),
  ];
  const markers = <String>[
    'downbook.php',
    '/download/',
    'downajax',
    '.zip',
    '.rar',
    '.epub',
    '.txt',
  ];
  return urls.any((url) => markers.any(url.contains));
}

CheckIssue repeatedTextIssue(
  ({BookChapter chapter, String content}) a,
  ({BookChapter chapter, String content}) b,
  List<String> shared,
  CheckMode mode,
) {
  final prefix = mode == CheckMode.search ? '' : '發現書籍';
  String title(BookChapter chapter) => compactChapterTitle(chapter.title);
  String quote(String text) =>
      text.length > 30 ? '${text.substring(0, 30)}…' : text;
  // 一章把另一章的開頭也抓進來：說哪一章跨到哪一章。
  for (final (whole, part) in [(a, b), (b, a)]) {
    final opening = flatText(part.content);
    final head = opening.length > 30 ? opening.substring(0, 30) : opening;
    if (head.isNotEmpty &&
        !flatText(whole.content).startsWith(head) &&
        flatText(whole.content).contains(head)) {
      return CheckIssue(
        stage: checkStage(mode, 'content'),
        message:
            '$prefix${title(whole.chapter)}的正文把${title(part.chapter)}也抓進來了'
            '（下一頁的規則抓過頭，跨到別章）：「${quote(head)}」',
        health: contentHealthFor(mode),
      );
    }
  }
  final both = '${title(a.chapter)}與${title(b.chapter)}';
  final sharedText = shared.join('。');
  // 付費提示的句子不一定每句都有付費字樣（「開通會員可免費閱讀全站作品」），
  // 照句數算：三分之一以上帶付費字樣才算。故事重複時，帶「訂閱」的頁尾只是
  // 幾百句裡的一句。
  final paid = shared.where(hasPaidMarker).length;
  if (paid * 3 >= shared.length) {
    return CheckIssue(
      stage: checkStage(mode, 'content'),
      message: '$prefix$both的正文一半以上是同一段付費提示：「${quote(sharedText)}」',
      health: paidSourceHealth,
    );
  }
  return CheckIssue(
    stage: checkStage(mode, 'content'),
    message:
        '$prefix$both的正文一半以上是同一段文字（一章一章重複的內容）：'
        '「${quote(sharedText)}」',
    health: contentHealthFor(mode),
  );
}
