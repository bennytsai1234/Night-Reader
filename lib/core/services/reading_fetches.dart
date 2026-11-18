import 'dart:async';

/// 閱讀時正在向書源抓的東西：文字閱讀器抓沒存的章（含預先載入的下一章）、
/// 漫畫抓一章的圖片清單、有聲書抓一集的音訊。放到背景的搜尋送下一個書源前
/// 等它們抓完，閱讀的抓章插在搜尋前面（ADR 0070）。
class ReadingFetches {
  ReadingFetches._();

  static final ReadingFetches instance = ReadingFetches._();

  /// 最多等多久：抓章卡住時搜尋不跟著停。
  static const Duration longestWait = Duration(seconds: 10);

  int _active = 0;
  Completer<void>? _idle;

  /// 抓 [fetch]；抓的時候背景搜尋不送新的書源。
  Future<T> track<T>(Future<T> Function() fetch) async {
    _active++;
    try {
      return await fetch();
    } finally {
      _active--;
      if (_active == 0) {
        _idle?.complete();
        _idle = null;
      }
    }
  }

  /// 沒有在抓、或等了 [longestWait] 時完成。
  Future<void> idle() {
    if (_active == 0) return Future<void>.value();
    final idle = (_idle ??= Completer<void>()).future;
    return idle.timeout(longestWait, onTimeout: () {});
  }
}
