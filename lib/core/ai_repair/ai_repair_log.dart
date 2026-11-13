import 'dart:async';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/crash_handler.dart';

/// 一次 AI 修復的紀錄，分兩份（ADR 0054）：
/// - **摘要**（[summary]）：每一步的結論與花的時間、AI 每一輪下的指令與
///   用量、送出的請求與網站回應的開頭；同樣的回應只寫一次，太長時省略中間
///   幾輪，貼進聊天不會被截斷。「複製摘要」複製它。
/// - **完整紀錄**（[file]）：同樣的段落，加上照原樣送給 AI 的每一句話、AI
///   回的全文、每個請求網站回的整頁原文（不精簡、不截）。一面做一面寫進
///   崩潰日誌旁的 `ai-repair/` 資料夾，不留在記憶體；「分享完整紀錄」分享
///   這個檔。資料夾只留最近的 [_keptFiles] 個、合計 [_keptBytes] 以內。
///
/// 寫進來的每一段先經過 [redact]（遮掉登入資料、Cookie 與書源變數的值）。
final class AiRepairLog {
  AiRepairLog({
    required String sourceName,
    required String sourceUrl,
    Future<Directory> Function()? directory,
  }) : _directory = directory ?? _defaultDirectory,
       _fileName =
           '${DateFormat('yyyyMMdd-HHmmss-SSS').format(DateTime.now())}-'
           '${_safeName(sourceUrl)}-${_opened++}.txt' {
    _title = '# AI 修復：$sourceName（$sourceUrl）';
  }

  /// 一次 AI 找書的紀錄（ADR 0060）：和修復紀錄同一個資料夾、同樣的兩份，
  /// 檔名接 `find`。
  AiRepairLog.find({
    required String description,
    Future<Directory> Function()? directory,
  }) : _directory = directory ?? _defaultDirectory,
       _fileName =
           '${DateFormat('yyyyMMdd-HHmmss-SSS').format(DateTime.now())}-'
           'find-${_opened++}.txt' {
    _title = '# AI 找書：$description';
  }

  /// 這次開 App 以來開了幾份：同一毫秒開的兩份（整批修復同時修好幾個）
  /// 檔名也不同。
  static int _opened = 0;

  late final String _title;
  final String _fileName;
  final Future<Directory> Function() _directory;
  final Stopwatch _clock = Stopwatch()..start();
  final List<_Block> _blocks = [];
  final Set<String> _seenResponses = {};
  Future<void> _queue = Future<void>.value();
  File? _file;
  bool _fileFailed = false;

  /// 寫進來之前先遮掉的秘密；修復開始讀到書源的秘密後換掉。
  String Function(String text) redact = _same;

  static String _same(String text) => text;

  /// 還沒寫任何一段。
  bool get isEmpty => _blocks.isEmpty;

  /// 開頭：版本、AI 服務、提示詞的版本與開始時間。
  void header(String details, {String prompt = ''}) {
    final line = [
      if (CrashHandler.appVersionLine.isNotEmpty)
        '夜讀${CrashHandler.appVersionLine}',
      details,
      if (prompt.isNotEmpty) '提示詞 $prompt',
      DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
    ].join(' · ');
    _blocks.add(_Block(redact('$_title\n$line'), round: false));
    _write('$_title\n$line\n');
  }

  /// 新的一段，例如「校驗原本的書源」「第 3 輪」；[round] 是 AI 的一輪，
  /// 摘要太長時省略的是中間的這種段落。標題後面接開始的時間（從修復開始
  /// 算）。
  void section(String title, {bool round = false}) {
    final heading = '## $title（${_elapsed()}）';
    _blocks.add(_Block(redact(heading), round: round));
    _write('\n$heading\n');
  }

  /// 摘要與完整紀錄都寫的一段。
  void both(String text) {
    note(text);
    full(text);
  }

  /// 只寫進摘要的一段。
  void note(String text) {
    if (_blocks.isEmpty) _blocks.add(_Block(redact(_title), round: false));
    _blocks.last.lines.add(redact(text));
  }

  /// 只寫進完整紀錄的一段。
  void full(String text) => _write('$text\n');

  /// 送出的請求與網站的回應：摘要裡每個回應只留開頭 [_responseHead] 字，
  /// 前面出現過一樣的回應寫「內容同前」；完整紀錄寫 [pages] 的整頁原文。
  void requests(List<String> lines, {List<LoggedPage> pages = const []}) {
    if (lines.isNotEmpty) note(lines.map(_shortLine).join('\n'));
    if (pages.isNotEmpty) {
      final text = [
        for (final page in pages)
          page.body == null ? page.line : '${page.line}\n${page.body}',
      ].join('\n');
      full('### 請求與網站回的原文\n$text');
    } else if (lines.isNotEmpty) {
      full(lines.join('\n'));
    }
  }

  /// 照原樣送給 AI 的一句話（只寫進完整紀錄）。
  void message(String role, String content) =>
      full('### 送給 AI（$role，${content.length} 字）\n$content');

  /// 給 AI 用的工具清單（每件寫一次，只寫進完整紀錄）。
  void tools(String json) => full('### 工具\n$json');

  /// AI 呼叫的一個工具：完整紀錄寫名稱與參數全文，摘要只留開頭 [_replyHead] 字。
  void toolCall(String name, String arguments) {
    note('AI 呼叫 $name：${_clip(arguments.trim(), _replyHead)}');
    full('### AI 呼叫工具 $name（${arguments.length} 字）\n$arguments');
  }

  /// AI 的思考：只寫進完整紀錄，全文。
  void thinking(String text) => full('### AI 的思考（${text.length} 字）\n$text');

  /// AI 回的話：完整紀錄寫全文，摘要只留開頭 [_replyHead] 字。
  void reply(String text) {
    note('AI：${_clip(text.trim(), _replyHead)}');
    full('### AI 回覆（${text.length} 字）\n$text');
  }

  /// 摘要：太長時留下開頭、結尾，省略中間的幾輪。
  String get summary {
    String join(Iterable<_Block> blocks) =>
        blocks.map((block) => block.text).join('\n\n');
    final all = join(_blocks);
    if (all.length <= summaryLength) return all;
    final rounds = [
      for (final (i, block) in _blocks.indexed)
        if (block.round) i,
    ];
    final dropped = <int>{};
    // 從中間往外拿掉 AI 的輪，直到夠短或只剩第一輪與最後一輪。
    while (rounds.length - dropped.length > 2) {
      final left = [
        for (final i in rounds)
          if (!dropped.contains(i)) i,
      ];
      dropped.add(left[left.length ~/ 2]);
      final kept = [
        for (final (i, block) in _blocks.indexed)
          if (!dropped.contains(i)) block,
      ];
      if (join(kept).length + 60 <= summaryLength) break;
    }
    final out = <String>[];
    var skipped = <String>[];
    for (final (i, block) in _blocks.indexed) {
      if (dropped.contains(i)) {
        skipped.add(block.lines.first.replaceFirst('## ', ''));
        continue;
      }
      if (skipped.isNotEmpty) {
        out.add(
          '（省略 ${skipped.length} 輪：${skipped.first} 到 ${skipped.last}，見完整紀錄）',
        );
        skipped = [];
      }
      out.add(block.text);
    }
    final text = out.join('\n\n');
    return text.length <= summaryLength
        ? text
        : '${text.substring(0, summaryLength)}…（以下省略，見完整紀錄）';
  }

  /// 摘要最多幾個字。
  static const int summaryLength = 8000;

  /// 完整紀錄寫完後的檔案；寫不了（例如沒有存放的資料夾）是 null。
  Future<File?> file() async {
    await _queue;
    return _fileFailed ? null : _file;
  }

  String _elapsed() {
    final seconds = _clock.elapsed.inSeconds;
    return '+${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  /// 摘要裡的一行請求或回應：回應只留開頭，前面有一樣的寫「內容同前」。
  String _shortLine(String line) {
    final match = RegExp(
      r'^(  ← \S+ [^：]*)：(.*)$',
      dotAll: true,
    ).firstMatch(line);
    if (match == null) return _clip(line, _responseHead * 2);
    final head = match.group(1)!;
    final body = match.group(2)!;
    final key = '$head\n$body';
    if (!_seenResponses.add(key)) return '$head（內容同前）';
    return '$head：${_clip(body, _responseHead)}';
  }

  static String _clip(String text, int length) =>
      text.length <= length ? text : '${text.substring(0, length)}…';

  void _write(String text) {
    final redacted = redact(text);
    _queue = _queue.then((_) async {
      if (_fileFailed) return;
      try {
        final file = _file ??= await _open();
        await file.writeAsString(redacted, mode: FileMode.append, flush: true);
      } catch (error) {
        _fileFailed = true;
        AppLog.w('AI 修復的完整紀錄寫不進去: $error');
      }
    });
  }

  Future<File> _open() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    await _prune(directory, room: 1);
    return File('${directory.path}/$_fileName');
  }

  /// 這一件寫完了：再修剪一次資料夾，這份寫完後合計超過 [_keptBytes] 的，
  /// 刪掉較舊的（這一份留著）。開檔時只量得到舊的，寫完才知道這份多大。
  void finish() {
    _queue = _queue.then((_) async {
      final file = _file;
      if (_fileFailed || file == null) return;
      try {
        await _prune(file.parent, keep: file.path);
      } catch (error) {
        AppLog.w('AI 修復的完整紀錄修剪不了: $error');
      }
    });
  }

  /// 只留最近的 [_keptFiles] 個、合計 [_keptBytes] 以內：從新的往舊的數，
  /// 超過的刪掉。[room] 是要騰出的位置（開新檔時是 1）；[keep] 那份不刪。
  static Future<void> _prune(
    Directory directory, {
    int room = 0,
    String? keep,
  }) async {
    final files = [
      for (final entity in directory.listSync())
        if (entity is File && entity.path.endsWith('.txt')) entity,
    ]..sort((a, b) => b.path.compareTo(a.path));
    var bytes = 0;
    for (final (i, file) in files.indexed) {
      bytes += file.lengthSync();
      if (file.path == keep) continue;
      // 寫完時修剪：同時修的別件還在寫自己那份，最近動過的不刪。
      if (keep != null &&
          DateTime.now().difference(file.lastModifiedSync()) < _stillWriting) {
        continue;
      }
      if (i >= _keptFiles - room || bytes > _keptBytes) {
        try {
          file.deleteSync();
        } on FileSystemException {
          // 刪不掉的下次再刪。
        }
      }
    }
  }

  static const int _keptFiles = 100;
  static const int _keptBytes = 50 * 1024 * 1024;

  /// 這麼久內動過的紀錄檔當成還在寫。
  static const Duration _stillWriting = Duration(minutes: 10);

  static const int _responseHead = 200;
  static const int _replyHead = 800;

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await CrashHandler.logDirectory()).path}/ai-repair');

  static String _safeName(String url) {
    final host = Uri.tryParse(url.trim())?.host ?? '';
    final name = (host.isEmpty ? url : host).replaceAll(
      RegExp(r'[^A-Za-z0-9.-]+'),
      '_',
    );
    return name.length > 60 ? name.substring(0, 60) : name;
  }
}

/// 摘要的一段：標題與內容。
final class _Block {
  _Block(String heading, {required this.round}) : lines = [heading];

  final bool round;
  final List<String> lines;

  String get text => lines.join('\n');
}
