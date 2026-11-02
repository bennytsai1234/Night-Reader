import 'dart:math' as math;

import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/core/sync/read_stats_sync.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/grouped_list_skeleton.dart';

class ReadingStatsPage extends StatefulWidget {
  const ReadingStatsPage({super.key});

  @override
  State<ReadingStatsPage> createState() => _ReadingStatsPageState();
}

typedef _Stats = ({List<_BookTime> records, int today, int week});

/// 一本書在所有手機上加起來讀了多久。
typedef _BookTime = ({String bookName, int readTime, int lastRead});

class _ReadingStatsPageState extends State<ReadingStatsPage> {
  late final ReadRecordDao _readRecordDao;
  late Future<_Stats> _stats;

  @override
  void initState() {
    super.initState();
    _readRecordDao = getIt<ReadRecordDao>();
    _stats = _load();
  }

  /// 這台的加上同步來的別台的（ADR 0039）。
  Future<_Stats> _load() async {
    final now = DateTime.now();
    final records = await _readRecordDao.getAllShow();
    final recent = await _readRecordDao.recentTotals(now);
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
  Future<OtherDevicesStats> _othersStats() async {
    try {
      return await ReadStatsSync.others();
    } catch (error, stackTrace) {
      AppLog.e('讀別台的閱讀統計失敗', error: error, stackTrace: stackTrace);
      return OtherDevicesStats.empty;
    }
  }

  /// 紀錄只有書名。書還在（書架上優先，其次最近讀的那本）就開書籍詳情；
  /// 已經移除的書找不到，改用書名搜尋。
  Future<void> _openBook(String bookName) async {
    final books = await getIt<BookDao>().getByName(bookName);
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
            : SearchPage(initialQuery: bookName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '閱讀統計'),
      body: FutureBuilder<_Stats>(
        future: _stats,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return AppStateView(
              icon: Icons.error_outline,
              title: '閱讀統計載入失敗',
              description: userErrorReason(snapshot.error!),
              tone: AppStateTone.error,
              primaryAction: AppStateAction(
                label: '重新載入',
                icon: Icons.refresh,
                onPressed: () => setState(() => _stats = _load()),
              ),
            );
          }

          final stats = snapshot.data!;
          final records = stats.records;
          if (records.isEmpty) {
            return const AppStateView(
              icon: Icons.history_rounded,
              title: '尚無閱讀紀錄',
              description: '開始閱讀一本書之後，這裡會顯示你的累積閱讀時間。',
            );
          }

          final total = records.fold<int>(0, (sum, r) => sum + r.readTime);
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
              GroupedSection(
                header: '累積閱讀時間',
                children: [
                  for (final record in records)
                    GroupedRow(
                      // 顯示時做繁簡轉換，和書架一致；找書仍用原文。
                      title: context.zh(record.bookName),
                      value: _formatDuration(record.readTime),
                      onTap: () => _openBook(record.bookName),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

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
      label: '$label $value $unit',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: _padding),
        child: Column(
          children: [
            Text.rich(
              _valueSpan(scheme),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: _labelGap),
            Text(
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
