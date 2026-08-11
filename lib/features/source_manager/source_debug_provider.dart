import 'dart:async';
import 'package:night_reader/core/base/base_provider.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/source_debug_service.dart';

class SourceDebugProvider extends BaseProvider {
  final BookSource source;
  final String key;
  final SourceDebugService _debugService;
  StreamSubscription<DebugLog>? _subscription;

  final List<DebugLog> _logs = [];
  List<DebugLog> get logs => List<DebugLog>.unmodifiable(_logs);

  bool _isFinished = false;
  bool get isFinished => _isFinished;
  bool _isRunning = false;
  bool get isRunning => _isRunning;
  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  SourceDebugProvider(this.source, this.key, {SourceDebugService? debugService})
    : _debugService = debugService ?? SourceDebugService();

  Future<void> startDebug() async {
    if (_isDisposed || _isRunning) return;
    _isRunning = true;
    _logs.clear();
    _isFinished = false;
    notifyListeners();
    await _subscription?.cancel();
    if (_isDisposed) return;

    _subscription = _debugService.logStream.listen((log) {
      if (_isDisposed) return;
      _logs.add(log);
      if (log.state == 1000 || log.state == -1) {
        _isFinished = true;
      }
      notifyListeners();
    });

    try {
      await _debugService.startDebug(source, key);
    } catch (error) {
      if (!_isDisposed) {
        _logs.add(DebugLog(-1, '調試失敗：$error', DateTime.now()));
        _isFinished = true;
      }
    } finally {
      if (!_isDisposed) {
        _isRunning = false;
        _isFinished = true;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_subscription?.cancel());
    _debugService.cancel();
    super.dispose();
  }
}
