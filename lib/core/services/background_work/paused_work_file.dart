import 'dart:async';
import 'dart:io';

import 'package:night_reader/core/services/app_log_service.dart';
import 'package:path_provider/path_provider.dart';

/// 一件背景工作做到哪裡的存檔：每做完一步（AI 找書的一輪、校驗的一個書源）
/// 存一次，App 被收掉或從最近使用滑掉之後，下次開 App 照它顯示「已暫停」、
/// 按繼續從這裡接著做（ADR 0058）。一件一個檔，不同步、不進夜讀的備份。
///
/// - 寫入排隊：上一次還沒寫完時又存，只寫最後那份。先寫到暫存檔再改名，
///   寫到一半被收掉也留著上一份完整的。
/// - [close] 之後不再寫：使用者按了結束的工作不能從晚到的那次寫入活回來。
/// - 同名的幾個存檔（上一件還在收尾、下一件已經開始）的寫入與刪除排成一列，
///   而且只有最後寫的那個能刪：舊的那件收尾時不會刪掉新的那件剛存的檔。
class PausedWorkFile {
  PausedWorkFile(this.name, {Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  /// 檔名（不含副檔名），一種工作一個：`ai_find`、`check_sources`…
  final String name;
  final Future<Directory> Function() _directory;

  String Function()? _pending;
  Future<void>? _writing;
  bool _closed = false;

  /// 每個檔名最後寫的是哪一個存檔；沒人寫過是不在表裡。
  static final Map<String, PausedWorkFile> _owners = {};

  /// 每個檔名的寫入與刪除排成一列。
  static final Map<String, Future<void>> _queues = {};

  Future<void> _serial(Future<void> Function() work) {
    final done = (_queues[name] ?? Future<void>.value()).then((_) => work());
    _queues[name] = done.catchError((Object _) {});
    return done;
  }

  /// 已經結束，不再寫。
  bool get isClosed => _closed;

  /// 存檔的內容；沒有存檔或讀不到是 null。
  Future<String?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (error) {
      AppLog.w('PausedWorkFile: 讀不到 $name：$error');
      return null;
    }
  }

  /// 存 [text]（排隊，見類別說明）；結束之後不理。
  void save(String text) => saveLater(() => text);

  /// 要寫的時候才呼叫 [encode] 編成文字：上一次還沒寫完時連續存好幾次，只編
  /// 最後那次（校驗每做完一個書源就存，600 個書源的進度編一次要 2 ms）。
  /// 只給之後不會再改的、或改了也照寫當下樣子沒關係的狀態用。
  void saveLater(String Function() encode) {
    if (_closed) return;
    _pending = encode;
    _writing ??= _drain();
  }

  /// 寫完排著的那份；測試等它。
  Future<void> flush() async {
    for (var writing = _writing; writing != null; writing = _writing) {
      await writing;
    }
  }

  Future<void> _drain() async {
    try {
      for (var next = _pending; next != null && !_closed; next = _pending) {
        _pending = null;
        try {
          final text = next();
          await _serial(() async {
            if (_closed) return;
            final file = await _file();
            await file.parent.create(recursive: true);
            final temp = File('${file.path}.${identityHashCode(this)}.tmp');
            await temp.writeAsString(text, flush: true);
            if (_closed) {
              await temp.delete();
              return;
            }
            await temp.rename(file.path);
            _owners[name] = this;
          });
        } catch (error) {
          AppLog.w('PausedWorkFile: 存不進 $name：$error');
        }
      }
    } finally {
      _writing = null;
    }
  }

  /// 這件工作結束了：之後的 [save] 都不理，存檔刪掉。等正在寫的那次寫完再刪，
  /// 不會被它寫回來。
  /// 同名的另一個存檔後來寫過時不刪：那是下一件工作的。
  Future<void> close() async {
    _closed = true;
    _pending = null;
    await flush();
    try {
      await _serial(() async {
        final owner = _owners[name];
        if (owner != null && !identical(owner, this)) return;
        _owners.remove(name);
        final file = await _file();
        if (await file.exists()) await file.delete();
      });
    } catch (error) {
      AppLog.w('PausedWorkFile: 刪不掉 $name：$error');
    }
  }

  Future<File> _file() async => File('${(await _directory()).path}/$name.json');

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/paused_work');
}
