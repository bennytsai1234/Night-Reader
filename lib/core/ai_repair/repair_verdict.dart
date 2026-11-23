import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/engine/web_book/book_list_parser.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source_check/source_check_isolate.dart';

import 'ai_repair_prompt.dart';

/// 校驗的結果可以存：沒問題；或原本搜尋、閱讀有壞（[before] 不是只壞
/// 發現頁），現在只剩發現頁失效、而 AI 沒動發現頁用的規則（[_touchedDiscovery]）
/// ——發現頁原本就壞了，搜尋與閱讀修好了還是比原本好。原本就只壞發現頁、
/// 或不知道原本壞在哪（[before] 是 null）的，要整個沒問題才算。
bool usableFix(
  SourceCheckIsolateResult? result,
  BookSource original,
  BookSource candidate, {
  required SourceHealthCategory? before,
}) {
  if (result == null) return false;
  if (result.isHealthy) return true;
  if (before == null || _discoveryOnly.contains(before)) return false;
  return _onlyDiscoveryFails(result) && !_touchedDiscovery(original, candidate);
}

bool _onlyDiscoveryFails(SourceCheckIsolateResult result) =>
    _discoveryOnly.contains(
      BookSource.fromJson(result.updatedSourceJson).runtimeHealth.category,
    );

/// AI 動了發現頁用的規則：改了發現的規則，或改了搜尋規則、而發現頁用搜尋
/// 規則解析（[BookListParser.exploreUsesSearchRule]）。2026-11-12 實跑
/// 涨姿势：發現沒有自己的書單規則，AI 把搜尋改成網站的 API，發現頁跟著
/// 抓不到書，卻照「AI 沒動發現」收下。
bool _touchedDiscovery(BookSource original, BookSource candidate) {
  final parts = changedParts(original, candidate);
  if (parts.contains('發現')) return true;
  return parts.contains('搜尋') &&
      (BookListParser.exploreUsesSearchRule(original) ||
          BookListParser.exploreUsesSearchRule(candidate));
}

/// 只剩發現頁沒過、AI 改了發現頁借用的搜尋規則時，回給 AI 的那一句事實。
String? discoveryNote(
  SourceCheckIsolateResult? result,
  BookSource original,
  BookSource candidate,
) {
  if (result == null || !_onlyDiscoveryFails(result)) return null;
  final parts = changedParts(original, candidate);
  if (parts.contains('發現') || !parts.contains('搜尋')) return null;
  if (!_touchedDiscovery(original, candidate)) return null;
  return aiRepairExploreBorrowsSearch;
}

const Set<SourceHealthCategory> _discoveryOnly = {
  SourceHealthCategory.discoveryBroken,
  SourceHealthCategory.discoveryDetailBroken,
  SourceHealthCategory.discoveryTocBroken,
  SourceHealthCategory.discoveryContentBroken,
};

/// AI 回的書源照原本的身分組起來（[creating] 見 [candidateFrom]）；欄位的
/// 型別或數值不對（例如超出範圍的數字）時是 null，當成讀不懂。
BookSource? candidateOrNull(
  BookSource original,
  Map<String, dynamic> json, {
  bool creating = false,
}) {
  try {
    return candidateFrom(original, json, creating: creating);
  } catch (error) {
    AppLog.d('AI 回的書源讀不出來: $error');
    return null;
  }
}
