import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/source/source_site.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/background_work/background_work.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/check_source_service.dart';

/// 重複書源（ADR 0062）：同一個網站（[siteHost]，和「按域名分組」同一個
/// 分法）、同一類（`bookSourceType`）的書源。每組照 [keeperOrder] 排好，
/// 第一個留下；只有一個的不列。書源清單的精簡書源沒有規則，認不出聚合源，
/// 這裡分出來的是候選，合併前照完整書源再分一次（[mergeDuplicateSources]）。
List<List<BookSource>> duplicateSourceGroups(Iterable<BookSource> sources) {
  final groups = <(String, int, bool), List<BookSource>>{};
  for (final source in sources) {
    final host = siteHost(source.bookSourceUrl);
    if (host == null) continue;
    groups
        .putIfAbsent((
          host,
          source.bookSourceType,
          source.isAggregateSource,
        ), () => [])
        .add(source);
  }
  return [
    for (final group in groups.values)
      if (group.length > 1) group..sort(keeperOrder),
  ];
}

/// 一組重複書源留哪一個：沒有「異常」標記的、啟用的、手動排序在前的，
/// 最後照網址。只看會同步的欄位，兩台各自合併也留同一個（書架上的書數、
/// 最後更新時間各台不同）。
int keeperOrder(BookSource a, BookSource b) {
  int flag(bool value) => value ? 0 : 1;
  final byHealth = flag(!a.hasGroupTag(abnormalSourceGroupTag))
      .compareTo(flag(!b.hasGroupTag(abnormalSourceGroupTag)));
  if (byHealth != 0) return byHealth;
  final byEnabled = flag(a.enabled).compareTo(flag(b.enabled));
  if (byEnabled != 0) return byEnabled;
  final byOrder = a.customOrder.compareTo(b.customOrder);
  if (byOrder != 0) return byOrder;
  return a.bookSourceUrl.compareTo(b.bookSourceUrl);
}

/// 書源校驗、修復這類批次工作在跑時不併：它們正在用、正在改這些書源，
/// 做完之後書源管理重讀清單時再併。
bool _sourcesIdle() =>
    !BackgroundWork.instance.isBusy &&
    !(getIt.isRegistered<CheckSourceService>() &&
        getIt<CheckSourceService>().isChecking);

/// 把重複書源併成一個（[BookSourceService.mergeSources]）：書架上的書、搜尋
/// 紀錄與快取的正文搬到留下的那個，重複的刪掉。[sources] 是已經讀好的
/// 書源清單（不給就讀一次）。批次工作在跑時什麼都不做。傳回真的併掉幾個。
///
/// 聚合源（ADR 0056）和一般書源不併：聚合源的書各自是哪一類，併進一般書源
/// 會跟著它的類型，漫畫、有聲書會變成小說。
Future<int> mergeDuplicateSources({
  List<BookSource>? sources,
  Future<List<String>> Function(List<String> from, String into)? merge,
  bool Function()? idle,
}) async {
  if (!(idle ?? _sourcesIdle)()) return 0;
  final dao = getIt<BookSourceDao>();
  final candidates = duplicateSourceGroups(sources ?? await dao.getAllPart());
  if (candidates.isEmpty) return 0;
  final mergeInto = merge ?? BookSourceService().mergeSources;
  var merged = 0;
  for (final candidate in candidates) {
    final full = [
      for (final source in candidate) ?await dao.getByUrl(source.bookSourceUrl),
    ];
    for (final [keeper, ...rest] in duplicateSourceGroups(full)) {
      try {
        merged += (await mergeInto([
          for (final source in rest) source.bookSourceUrl,
        ], keeper.bookSourceUrl)).length;
      } catch (error, stack) {
        AppLog.e(
          '合併重複書源失敗：${keeper.bookSourceUrl}',
          error: error,
          stackTrace: stack,
        );
      }
    }
  }
  return merged;
}
