import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/read_record.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

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
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '閱讀統計'),
      body: FutureBuilder<List<ReadRecord>>(
        future: _records,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return AppStateView(
              icon: Icons.error_outline,
              title: '閱讀統計載入失敗',
              description: snapshot.error.toString(),
              tone: AppStateTone.error,
              primaryAction: AppStateAction(
                label: '重新載入',
                icon: Icons.refresh,
                onPressed: () {
                  setState(() {
                    _records = _readRecordDao.getAllShow();
                  });
                },
              ),
            );
          }

          final records = snapshot.data ?? const <ReadRecord>[];
          if (records.isEmpty) {
            return const AppStateView(
              icon: Icons.history_rounded,
              title: '尚無閱讀紀錄',
              description: '開始閱讀一本書之後，這裡會顯示你的累積閱讀時間。',
            );
          }

          return GroupedListView(
            children: [
              GroupedSection(
                header: '累積閱讀時間',
                footer: '點一本書即可搜尋該書。',
                children: [
                  for (final record in records)
                    GroupedRow(
                      title: record.bookName,
                      value: _formatDuration(record.readTime),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => SearchPage(initialQuery: record.bookName),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ],
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
