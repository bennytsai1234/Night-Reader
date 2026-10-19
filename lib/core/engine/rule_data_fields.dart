import 'dart:convert';

import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';

/// 規則 JS 能直接改的一個欄位（`book.xxx = …`、`chapter.xxx = …`）。
///
/// 這份清單是唯一的來源：JS 橋接照它寫入（`JsExtensions`），書源工作在書源
/// isolate 的複本上跑完後也照它把改過的欄位抄回呼叫端
/// （`BookSourceService`，ADR 0028）。讓規則能改新的欄位，只要加在這裡。
final class RuleDataField<T> {
  const RuleDataField(this.read, this.write, {this.merge});

  final Object? Function(T target) read;

  /// 寫入規則給的值，型別不對時照 JS 的習慣轉換。
  final void Function(T target, Object? value) write;

  /// 把一個工作在複本上從 `before` 改成 `after` 的結果，合併進呼叫端目前
  /// 的值；沒有時直接寫入 `after`。
  final Object? Function(Object? current, Object? before, Object? after)? merge;
}

final Map<String, RuleDataField<Book>> bookRuleFields = {
  'bookUrl': RuleDataField((b) => b.bookUrl, (b, v) => b.bookUrl = _string(v)),
  'tocUrl': RuleDataField((b) => b.tocUrl, (b, v) => b.tocUrl = _string(v)),
  'origin': RuleDataField((b) => b.origin, (b, v) => b.origin = _string(v)),
  'originName': RuleDataField(
    (b) => b.originName,
    (b, v) => b.originName = _string(v),
  ),
  'name': RuleDataField((b) => b.name, (b, v) => b.name = _string(v)),
  'author': RuleDataField((b) => b.author, (b, v) => b.author = _string(v)),
  'kind': RuleDataField((b) => b.kind, (b, v) => b.kind = _nullableString(v)),
  'coverUrl': RuleDataField(
    (b) => b.coverUrl,
    (b, v) => b.coverUrl = _nullableString(v),
  ),
  'intro': RuleDataField(
    (b) => b.intro,
    (b, v) => b.intro = _nullableString(v),
  ),
  'latestChapterTitle': RuleDataField(
    (b) => b.latestChapterTitle,
    (b, v) => b.latestChapterTitle = _nullableString(v),
  ),
  'wordCount': RuleDataField(
    (b) => b.wordCount,
    (b, v) => b.wordCount = _nullableString(v),
  ),
  'type': RuleDataField(
    (b) => b.type,
    (b, v) => b.type = _int(v, fallback: b.type),
  ),
  'chapterIndex': RuleDataField(
    (b) => b.chapterIndex,
    (b, v) => b.chapterIndex = _int(v, fallback: b.chapterIndex),
  ),
  // `book.putVariable` 也寫在這裡。
  'variable': RuleDataField(
    (b) => b.variable,
    (b, v) => b.variable = _nullableString(v),
    merge: _mergeVariables,
  ),
  'isInBookshelf': RuleDataField(
    (b) => b.isInBookshelf,
    (b, v) => b.isInBookshelf = _bool(v, fallback: b.isInBookshelf),
  ),
  'reverseToc': RuleDataField(
    (b) => b.readConfig?.reverseToc,
    (b, v) => (b.readConfig ??= ReadConfig()).reverseToc = _bool(
      v,
      fallback: b.readConfig?.reverseToc ?? false,
    ),
  ),
  'useReplaceRule': RuleDataField(
    (b) => b.readConfig?.useReplaceRule,
    (b, v) => (b.readConfig ??= ReadConfig()).useReplaceRule = _bool(
      v,
      fallback: b.readConfig?.useReplaceRule ?? false,
    ),
  ),
};

final Map<String, RuleDataField<SearchBook>> searchBookRuleFields = {
  'bookUrl': RuleDataField((b) => b.bookUrl, (b, v) => b.bookUrl = _string(v)),
  'name': RuleDataField((b) => b.name, (b, v) => b.name = _string(v)),
  'author': RuleDataField(
    (b) => b.author,
    (b, v) => b.author = _nullableString(v),
  ),
  'kind': RuleDataField((b) => b.kind, (b, v) => b.kind = _nullableString(v)),
  'coverUrl': RuleDataField(
    (b) => b.coverUrl,
    (b, v) => b.coverUrl = _nullableString(v),
  ),
  'intro': RuleDataField(
    (b) => b.intro,
    (b, v) => b.intro = _nullableString(v),
  ),
  'wordCount': RuleDataField(
    (b) => b.wordCount,
    (b, v) => b.wordCount = _nullableString(v),
  ),
  'latestChapterTitle': RuleDataField(
    (b) => b.latestChapterTitle,
    (b, v) => b.latestChapterTitle = _nullableString(v),
  ),
  'origin': RuleDataField((b) => b.origin, (b, v) => b.origin = _string(v)),
  'originName': RuleDataField(
    (b) => b.originName,
    (b, v) => b.originName = _nullableString(v),
  ),
  'originOrder': RuleDataField(
    (b) => b.originOrder,
    (b, v) => b.originOrder = _int(v, fallback: b.originOrder),
  ),
  'type': RuleDataField(
    (b) => b.type,
    (b, v) => b.type = _int(v, fallback: b.type),
  ),
  'variable': RuleDataField(
    (b) => b.variable,
    (b, v) => b.variable = _nullableString(v),
    merge: _mergeVariables,
  ),
  'tocUrl': RuleDataField(
    (b) => b.tocUrl,
    (b, v) => b.tocUrl = _nullableString(v),
  ),
  'respondTime': RuleDataField(
    (b) => b.respondTime,
    (b, v) => b.respondTime = _int(v, fallback: b.respondTime),
  ),
};

final Map<String, RuleDataField<BookChapter>> chapterRuleFields = {
  'url': RuleDataField((c) => c.url, (c, v) => c.url = _string(v)),
  'title': RuleDataField((c) => c.title, (c, v) => c.title = _string(v)),
  'baseUrl': RuleDataField((c) => c.baseUrl, (c, v) => c.baseUrl = _string(v)),
  'bookUrl': RuleDataField((c) => c.bookUrl, (c, v) => c.bookUrl = _string(v)),
  'index': RuleDataField(
    (c) => c.index,
    (c, v) => c.index = _int(v, fallback: c.index),
  ),
  'isVolume': RuleDataField(
    (c) => c.isVolume,
    (c, v) => c.isVolume = _bool(v, fallback: c.isVolume),
  ),
  'isVip': RuleDataField(
    (c) => c.isVip,
    (c, v) => c.isVip = _bool(v, fallback: c.isVip),
  ),
  'isPay': RuleDataField(
    (c) => c.isPay,
    (c, v) => c.isPay = _bool(v, fallback: c.isPay),
  ),
  'resourceUrl': RuleDataField(
    (c) => c.resourceUrl,
    (c, v) => c.resourceUrl = _nullableString(v),
  ),
  'tag': RuleDataField((c) => c.tag, (c, v) => c.tag = _nullableString(v)),
  'wordCount': RuleDataField(
    (c) => c.wordCount,
    (c, v) => c.wordCount = _nullableString(v),
  ),
  'start': RuleDataField((c) => c.start, (c, v) => c.start = _nullableInt(v)),
  'end': RuleDataField((c) => c.end, (c, v) => c.end = _nullableInt(v)),
  'startFragmentId': RuleDataField(
    (c) => c.startFragmentId,
    (c, v) => c.startFragmentId = _nullableString(v),
  ),
  'endFragmentId': RuleDataField(
    (c) => c.endFragmentId,
    (c, v) => c.endFragmentId = _nullableString(v),
  ),
  // `chapter.putVariable` 也寫在這裡。
  'variable': RuleDataField(
    (c) => c.variable,
    (c, v) => c.variable = _nullableString(v),
    merge: _mergeVariables,
  ),
  'content': RuleDataField(
    (c) => c.content,
    (c, v) => c.content = _nullableString(v),
  ),
};

/// `putVariable` 一次改一個鍵，同一本書常同時有好幾章在抓：只把這個工作增刪
/// 的鍵合併進目前的值，不拿複本的整串蓋掉別的工作剛寫進的鍵。任一邊不是
/// JSON 物件時（規則直接設成別的字串），照整串寫入。
Object? _mergeVariables(Object? current, Object? before, Object? after) {
  final was = _variableMap(before);
  final now = _variableMap(after);
  final merged = _variableMap(current);
  if (was == null || now == null || merged == null) return after;
  for (final key in was.keys) {
    if (!now.containsKey(key)) merged.remove(key);
  }
  for (final MapEntry(:key, :value) in now.entries) {
    if (was[key] != value) merged[key] = value;
  }
  return merged.isEmpty ? after : jsonEncode(merged);
}

Map<String, Object?>? _variableMap(Object? value) {
  if (value == null || value == '') return {};
  try {
    final decoded = jsonDecode(value.toString());
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  } on FormatException {
    return null;
  }
}

String _string(Object? value) => value?.toString() ?? '';

String? _nullableString(Object? value) => value?.toString();

int _int(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

bool _bool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  final normalized = value?.toString().trim().toLowerCase();
  if (normalized == 'true' || normalized == '1') return true;
  if (normalized == 'false' || normalized == '0') return false;
  return fallback;
}
