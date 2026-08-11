import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/services/app_log_service.dart';

class ReaderV2ReadTimeController {
  ReaderV2ReadTimeController({
    required this.bookName,
    required this.readRecordDao,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String bookName;
  final ReadRecordDao readRecordDao;
  final DateTime Function() _now;

  DateTime? _startedAt;
  Future<void> _writeTail = Future<void>.value();
  bool _closed = false;

  bool get isRunning => _startedAt != null;

  void start() {
    if (_closed || _startedAt != null) return;
    _startedAt = _now();
  }

  Future<void> stop() async {
    if (_closed) return;
    final startedAt = _startedAt;
    if (startedAt == null) return;

    _startedAt = null;
    final stoppedAt = _now();
    final seconds = stoppedAt.difference(startedAt).inSeconds;
    if (seconds <= 0) return;

    final write = _writeTail.then<void>(
      (_) => _persist(seconds, stoppedAt),
      onError: (Object _, StackTrace __) => _persist(seconds, stoppedAt),
    );
    _writeTail = write;
    await write;
  }

  Future<void> close() async {
    if (_closed) return;
    await stop();
    _closed = true;
    await _writeTail;
  }

  Future<void> _persist(int seconds, DateTime stoppedAt) async {
    try {
      await readRecordDao.recordReadActivity(
        bookName: bookName,
        seconds: seconds,
        lastRead: stoppedAt.millisecondsSinceEpoch,
      );
    } catch (e, stack) {
      AppLog.e(
        '寫入閱讀時間失敗: $e',
        error: e,
        stackTrace: stack,
      );
    }
  }
}
