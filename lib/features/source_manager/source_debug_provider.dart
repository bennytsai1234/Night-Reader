import 'dart:async';
import 'package:night_reader/core/base/base_provider.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/source_debug_service.dart';

class SourceDebugProvider extends BaseProvider {
  final BookSource source;
  final String key;
  final SourceDebugService _debugService = SourceDebugService();
  StreamSubscription? _subscription;

  final List<DebugLog> _logs = [];
  List<DebugLog> get logs => _logs;

  bool _isFinished = false;
  bool get isFinished => _isFinished;

  SourceDebugProvider(this.source, this.key);

  Future<void> startDebug() async {
    _logs.clear();
    _isFinished = false;
    _subscription?.cancel();

    _subscription = _debugService.logStream.listen((log) {
      _logs.add(log);
      if (log.state == 1000 || log.state == -1) {
        _isFinished = true;
      }
      notifyListeners();
    });

    await _debugService.startDebug(source, key);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _debugService.cancel();
    super.dispose();
  }
}
