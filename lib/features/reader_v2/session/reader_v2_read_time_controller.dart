import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/services/app_log_service.dart';

class ReaderV2ReadTimeController {
  ReaderV2ReadTimeController({
    required this.bookName,
    required this.readRecordDao,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// 寫入時才問書名：閱讀統計照書名記，閱讀中從書籍詳情改了書名，回來
  /// 讀的時間要記在新書名下（改名時舊的統計已經搬過去）。
  final Future<String> Function() bookName;
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
    if (stoppedAt.difference(startedAt).inSeconds <= 0) return;

    final write = _writeTail.then<void>(
      (_) => _persist(startedAt, stoppedAt),
      onError: (Object _, StackTrace _) => _persist(startedAt, stoppedAt),
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

  Future<void> _persist(DateTime startedAt, DateTime stoppedAt) async {
    try {
      await readRecordDao.recordReadActivity(
        bookName: await bookName(),
        startedAt: startedAt,
        stoppedAt: stoppedAt,
      );
    } catch (e, stack) {
      AppLog.e('寫入閱讀時間失敗: $e', error: e, stackTrace: stack);
    }
  }
}
