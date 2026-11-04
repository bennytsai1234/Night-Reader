import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/local_book_service.dart';

/// 把一段要讀整個檔的工作交給誰跑：預設背景 isolate；元件測試的假時間等不到
/// isolate 回覆時給直接跑的版本。
typedef LocalBookWorkRunner = Future<R> Function<R>(
  FutureOr<R> Function() work,
);

/// 本地書的檔案工作（算指紋、壓縮、解壓）都在背景 isolate 跑：大檔讀起來
/// 要幾百毫秒，不佔畫面的主執行緒（ADR 0046）。
Future<R> runLocalBookWorkInBackground<R>(FutureOr<R> Function() work) =>
    Isolate.run(work, debugName: 'local-book');

/// 本地書原檔內容的指紋（SHA-256，十六進位）。兩台手機匯入同一個檔算出來
/// 一樣，檔名不同也一樣（ADR 0039）。
Future<String> localBookFingerprint(
  String path, {
  LocalBookWorkRunner run = runLocalBookWorkInBackground,
}) => run(() => fingerprintOfFile(path));

/// 在目前的 isolate 讀 [path] 算指紋；要在背景 isolate 裡呼叫。
Future<String> fingerprintOfFile(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

/// 書架上還沒有原檔指紋的本地書（這一版以前匯入的）補算指紋，在背景
/// isolate 一次算完。原檔不見了的算不出來，留著空的。補到了就讓書架重讀，
/// 畫面上拿著的書換成有指紋的。傳回補到幾本。
Future<int> fillLocalBookFingerprints(
  BookDao bookDao, {
  LocalBookWorkRunner run = runLocalBookWorkInBackground,
}) async {
  final missing = [
    for (final book in await bookDao.getInBookshelf())
      if (book.isLocal && book.fileFingerprint == null) book,
  ];
  if (missing.isEmpty) return 0;
  final paths = {
    for (final book in missing) book.bookUrl: LocalBookService.filePathOf(book),
  };
  final prints = await _fingerprintsOn(run, paths);
  for (final MapEntry(key: url, value: print) in prints.entries) {
    await bookDao.updateFileFingerprint(url, print);
  }
  if (prints.isNotEmpty) AppEventBus().fire(AppEventBus.upBookshelf);
  return prints.length;
}

// 閉包在頂層函式裡建立，只捕捉 [paths]（CODING_STANDARDS.md）。
Future<Map<String, String>> _fingerprintsOn(
  LocalBookWorkRunner run,
  Map<String, String> paths,
) => run(() => _fingerprintsOf(paths));

Future<Map<String, String>> _fingerprintsOf(Map<String, String> paths) async {
  final prints = <String, String>{};
  for (final MapEntry(key: url, value: path) in paths.entries) {
    if (!File(path).existsSync()) continue;
    try {
      prints[url] = await fingerprintOfFile(path);
    } on FileSystemException {
      // 讀不了的檔跳過，下次再試。
    }
  }
  return prints;
}
