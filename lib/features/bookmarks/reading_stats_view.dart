import 'dart:async';
import 'dart:math' as math;

import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/shared/widgets/book/book_kind_mark.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/chinese/chinese_display.dart';
import 'package:night_reader/core/sync/read_stats_sync.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/text/drag_overflow_text.dart';
import 'package:night_reader/core/chinese/ui_language.dart';

/// 閱讀紀錄頁的「統計」（`BookmarksPage`）：頂端今天、本週、總計三格，下面
/// 各書讀了多久，含有聲書的收聽時間（docs/design/screens.md）。
class ReadingStatsView extends StatefulWidget {
  const ReadingStatsView({super.key, required this.memory});

  /// 讀好的統計：閱讀紀錄頁推入前就讀好（[ReadingStatsMemory.load]），點
  /// 「統計」直接畫出來；每次顯示時再安靜地重讀一次，讀完才換上。
  final ReadingStatsMemory memory;

  @override
  State<ReadingStatsView> createState() => _ReadingStatsViewState();
}

typedef _Stats = ({List<_BookTime> records, int today, int week});

/// [ReadingStatsView] 最近一次讀統計的結果，由放它的頁面留著。
class ReadingStatsMemory {
  _Stats? _stats;
  Object? _error;

  /// 讀一次統計記下來；讀不到時記下錯誤，畫面顯示載入失敗。[keepLast] 時
  /// 已經有統計就留著上一次的，只記日誌（同步後的重讀）。
  Future<void> load({bool keepLast = false}) async {
    try {
      _stats = await _loadStats();
      _error = null;
    } catch (error, stackTrace) {
      AppLog.e('讀取閱讀統計失敗', error: error, stackTrace: stackTrace);
      if (!keepLast || _stats == null) _error = error;
    }
  }

  /// 這台的加上同步來的別台的（ADR 0039）。
  static Future<_Stats> _loadStats() async {
    final dao = getIt<ReadRecordDao>();
    final now = DateTime.now();
    final records = await dao.getAllShow();
    final recent = await dao.recentTotals(now);
    final others = await _othersStats();
    final books = <String, _BookTime>{
      for (final record in records)
        record.bookName: (
          bookName: record.bookName,
          readTime: record.readTime,
          lastRead: record.lastRead,
        ),
    };
    for (final MapEntry(key: name, value: other) in others.books.entries) {
      final mine = books[name];
      books[name] = (
        bookName: name,
        readTime: (mine?.readTime ?? 0) + other.readTime,
        lastRead: mine == null || other.lastRead > mine.lastRead
            ? other.lastRead
            : mine.lastRead,
      );
    }
    final (:today, :weekStart) = ReadRecordDao.recentDays(now);
    return (
      records: books.values.toList()
        ..sort((a, b) => b.lastRead.compareTo(a.lastRead)),
      today: recent.today + others.secondsBetween(today, today),
      week: recent.week + others.secondsBetween(weekStart, today),
    );
  }

  /// 別台的統計讀不出來（檔壞了）就只顯示這台的。
  static Future<OtherDevicesStats> _othersStats() async {
    try {
      return await ReadStatsSync.others();
    } catch (error, stackTrace) {
      AppLog.e('讀別台的閱讀統計失敗', error: error, stackTrace: stackTrace);
      return OtherDevicesStats.empty;
    }
  }
}

/// 一本書在所有手機上加起來讀了多久。
typedef _BookTime = ({String bookName, int readTime, int lastRead});

class _ReadingStatsViewState extends State<ReadingStatsView> {
  @override
  void initState() {
    super.initState();
    unawaited(_reload());
    ReadStatsSync.applied.addListener(_othersSynced);
  }

  @override
  void dispose() {
    ReadStatsSync.applied.removeListener(_othersSynced);
    super.dispose();
  }

  /// 重讀統計，讀完才換上（不閃載入圈）。
  Future<void> _reload({bool keepLast = false}) async {
    await widget.memory.load(keepLast: keepLast);
    if (mounted) setState(() => _retrying = false);
  }

  /// 載入失敗後按了「重新載入」、還在讀：錯誤畫面留著，按鈕寫「重新載入中…」。
  bool _retrying = false;

  bool _syncReloadPending = false;

  /// 同步收到別台的統計：安靜地重讀。被別的頁面蓋著時等露出來才讀，不疊在
  /// 換頁動畫上（ADR 0018）。
  Future<void> _othersSynced() async {
    if (_syncReloadPending) return;
    _syncReloadPending = true;
    await TransitionSettled.uncovered(context);
    _syncReloadPending = false;
    if (!mounted) return;
    await _reload(keepLast: true);
  }

  static Widget? _kindMark(String recordName) {
    final kind = BookSourceKind.splitRecordName(recordName).kind;
    return BookKindMark.iconOf(kind) == null ? null : BookKindMark(kind);
  }

  /// 紀錄只有書名（漫畫、有聲帶類別前綴，ADR 0053）。書還在（書架上優先，
  /// 其次最近讀的那本）就開書籍詳情；已經移除的書找不到，改用書名搜尋。
  Future<void> _openBook(String bookName) async {
    final books = await getIt<BookDao>().getByRecordName(bookName);
    if (!mounted) return;
    Book? book;
    for (final candidate in books) {
      if (book == null ||
          (candidate.isInBookshelf && !book.isInBookshelf) ||
          (candidate.isInBookshelf == book.isInBookshelf &&
              candidate.durChapterTime > book.durChapterTime)) {
        book = candidate;
      }
    }
    final found = book;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => found != null
            ? BookDetailPage(book: found)
            : SearchPage(
                initialQuery: BookSourceKind.splitRecordName(bookName).name,
                initialKind: BookSourceKind.splitRecordName(bookName).kind,
              ),
      ),
    );
  }

  /// 失敗、沒有紀錄時的畫面，放在頁首下面（同書籤、標註）。
  Widget _state(BuildContext context, Widget child) => Padding(
    padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final error = widget.memory._error;
    if (error != null) {
      return _state(
        context,
        AppStateView(
          icon: Icons.error_outline,
          title: '閱讀統計載入失敗',
          description: userErrorReason(error),
          tone: AppStateTone.error,
          primaryAction: AppStateAction(
            label: _retrying ? '重新載入中…' : '重新載入',
            icon: Icons.refresh,
            onPressed: _retrying
                ? null
                : () {
                    setState(() => _retrying = true);
                    unawaited(_reload());
                  },
          ),
        ),
      );
    }

    // 推入前沒有先讀（只有直接放這個元件時）：讀完才畫。
    final stats = widget.memory._stats;
    if (stats == null) return const SizedBox.shrink();
    final records = stats.records;
    if (records.isEmpty) {
      return _state(
        context,
        const AppStateView(icon: Icons.history_rounded, title: '沒有閱讀紀錄'),
      );
    }

    final total = records.fold<int>(0, (sum, r) => sum + r.readTime);
    bool isListened(_BookTime record) =>
        BookSourceKind.splitRecordName(record.bookName).kind ==
        BookSourceKind.audio;
    final read = [
      for (final record in records)
        if (!isListened(record)) record,
    ];
    final listened = [
      for (final record in records)
        if (isListened(record)) record,
    ];
    return GroupedListView(
      children: [
        GroupedSection(
          children: [
            GroupedContent(
              child: _StatTiles([
                _StatTile(label: '今天', seconds: stats.today),
                _StatTile(label: '本週', seconds: stats.week),
                _StatTile(label: '總計', seconds: total),
              ]),
            ),
          ],
        ),
        // 收聽時間算進上面的合計，書分「閱讀」「收聽」兩組（使用者
        // 2026-11-09 在候選圖上選，ADR 0055）；沒聽過有聲書時照舊一組。
        if (listened.isEmpty)
          GroupedSection(
            children: [for (final record in read) _row(context, record)],
          )
        else ...[
          if (read.isNotEmpty)
            GroupedSection(
              children: [
                const GroupedRow(title: '閱讀', heading: true),
                for (final record in read) _row(context, record),
              ],
            ),
          GroupedSection(
            children: [
              const GroupedRow(title: '收聽', heading: true),
              for (final record in listened) _row(context, record),
            ],
          ),
        ],
      ],
    );
  }

  /// 一本書一列：顯示時做繁簡轉換，和書架一致；找書仍用原文。同名的
  /// 漫畫、有聲書書名後面帶記號（ADR 0053）。
  Widget _row(BuildContext context, _BookTime record) => GroupedRow(
    translateTitle: false,
    title: context.zh(BookSourceKind.splitRecordName(record.bookName).name),
    titleMark: _kindMark(record.bookName),
    value: _formatDuration(record.readTime),
    onTap: () => _openBook(record.bookName),
  );

  static String _formatDuration(int totalSeconds) {
    final seconds = totalSeconds < 0 ? 0 : totalSeconds;
    if (seconds < 60) return '$seconds 秒';

    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes 分鐘';

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) return '$hours 小時';
    return '$hours 小時 $remainingMinutes 分鐘';
  }
}

/// 頂端並排的幾格，等寬。
class _StatTiles extends StatelessWidget implements GroupedSkeletonItem {
  const _StatTiles(this.tiles);

  final List<_StatTile> tiles;

  /// 每一格的數字與標籤照字置中排，整列取最高的一格、各格垂直置中。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final tileWidth = width / tiles.length;
    final shapes = [
      for (final tile in tiles) tile.skeletonShape(context, width: tileWidth),
    ];
    final height = shapes.map((shape) => shape.height).reduce(math.max);
    return GroupedItemShape(
      height,
      marks: [
        for (final (index, shape) in shapes.indexed)
          ...shape.marksAt(
            Offset(index * tileWidth, (height - shape.height) / 2),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) =>
      Row(children: [for (final tile in tiles) Expanded(child: tile)]);
}

/// 頂端的一格：大數字配單位，下面一行標籤。一小時內寫分鐘，以上寫小時
/// （一位小數），三格並排放得下。
class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.seconds});

  final String label;
  final int seconds;

  static const double _padding = AppSpacing.sm;
  static const double _labelGap = AppSpacing.xs;

  (String, String) get _valueAndUnit {
    final minutes = (seconds < 0 ? 0 : seconds) ~/ 60;
    if (minutes < 60) return ('$minutes', '分鐘');
    final hours = minutes / 60;
    final text = hours >= 100
        ? hours.round().toString()
        : hours.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return (text, '小時');
  }

  /// 數字配單位；[scheme] 為 null 時不帶顏色（骨架只量字）。
  TextSpan _valueSpan(ColorScheme? scheme) {
    final (value, unit) = _valueAndUnit;
    return TextSpan(
      children: [
        TextSpan(
          text: value,
          style: AppTextStyles.titleXl.copyWith(color: scheme?.onSurface),
        ),
        TextSpan(
          text: ' $unit',
          style: AppTextStyles.uiSm.copyWith(color: scheme?.onSurfaceVariant),
        ),
      ],
    );
  }

  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final value = GroupedItemShape.rich(
      context,
      _valueSpan(null),
      width: width,
      maxLines: 1,
    ).centeredIn(width);
    final label = GroupedItemShape.text(
      context,
      this.label,
      style: AppTextStyles.uiSm,
      width: width,
    ).centeredIn(width);
    const valueTop = _padding;
    final labelTop = valueTop + value.height + _labelGap;
    return GroupedItemShape(
      labelTop + label.height + _padding,
      marks: [
        ...value.marksAt(const Offset(0, valueTop)),
        ...label.marksAt(Offset(0, labelTop)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (value, unit) = _valueAndUnit;
    return Semantics(
      container: true,
      label: context.ui('$label $value $unit'),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: _padding),
        child: Column(
          children: [
            DragOverflowText(
              child: UiText.rich(_valueSpan(scheme), maxLines: 1),
            ),
            const SizedBox(height: _labelGap),
            UiText(
              label,
              style: AppTextStyles.uiSm.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
