import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/read_record.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';

class ReadingStatsPage extends StatefulWidget {
  const ReadingStatsPage({super.key});

  @override
  State<ReadingStatsPage> createState() => _ReadingStatsPageState();
}

class _ReadingStatsPageState extends State<ReadingStatsPage> {
  late final ReadRecordDao _readRecordDao;
  late Future<List<ReadRecord>> _records;

  @override
  void initState() {
    super.initState();
    _readRecordDao = getIt<ReadRecordDao>();
    _records = _readRecordDao.getAllShow();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('閱讀統計')),
      body: FutureBuilder<List<ReadRecord>>(
        future: _records,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _records = _readRecordDao.getAllShow();
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新載入'),
                ),
              ),
            );
          }

          final records = snapshot.data ?? const <ReadRecord>[];
          if (records.isEmpty) {
            return const Center(child: Text('尚無閱讀紀錄'));
          }

          return ListTileTheme(
            data: const ListTileThemeData(
              contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            ),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              itemCount: records.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final record = records[index];
                return ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(
                    record.bookName,
                    style: AppTextStyles.bodyBase.copyWith(height: 1.35),
                  ),
                  subtitle: Text(
                    '累積閱讀 ${_formatDuration(record.readTime)}',
                    style: AppTextStyles.bodySm.copyWith(height: 1.4),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SearchPage(initialQuery: record.bookName),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
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
