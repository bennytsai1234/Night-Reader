import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/read_record.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

class ReadingStatsPage extends StatefulWidget {
  const ReadingStatsPage({super.key});

  @override
  State<ReadingStatsPage> createState() => _ReadingStatsPageState();
}

typedef _Stats = ({List<ReadRecord> records, int today, int week});

class _ReadingStatsPageState extends State<ReadingStatsPage> {
  late final ReadRecordDao _readRecordDao;
  late Future<_Stats> _stats;

  @override
  void initState() {
    super.initState();
    _readRecordDao = getIt<ReadRecordDao>();
    _stats = _load();
  }

  Future<_Stats> _load() async {
    final records = await _readRecordDao.getAllShow();
    final recent = await _readRecordDao.recentTotals(DateTime.now());
    return (records: records, today: recent.today, week: recent.week);
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
                    child: Row(
                      children: [
                        _StatTile(label: '今天', seconds: stats.today),
                        _StatTile(label: '本週', seconds: stats.week),
                        _StatTile(label: '總計', seconds: total),
                      ],
                    ),
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

/// 頂端的一格：大數字配單位，下面一行標籤。一小時內寫分鐘，以上寫小時
/// （一位小數），三格並排放得下。
class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.seconds});

  final String label;
  final int seconds;

  (String, String) get _valueAndUnit {
    final minutes = (seconds < 0 ? 0 : seconds) ~/ 60;
    if (minutes < 60) return ('$minutes', '分鐘');
    final hours = minutes / 60;
    final text = hours >= 100
        ? hours.round().toString()
        : hours.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return (text, '小時');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (value, unit) = _valueAndUnit;
    return Expanded(
      child: Semantics(
        container: true,
        label: '$label $value $unit',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: AppTextStyles.titleXl.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    TextSpan(
                      text: ' $unit',
                      style: AppTextStyles.uiSm.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                style: AppTextStyles.uiSm.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
