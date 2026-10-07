import 'package:flutter/services.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

/// 長按選詞用的斷詞。Flutter 引擎內建的 ICU 資料不含中文詞典，
/// `Paragraph.getWordBoundary` 對漢字只會逐字切；Android 系統的 ICU 帶有
/// 詞典，所以交給原生端 `BreakIterator` 斷詞。
final class WordSegmenter {
  const WordSegmenter();

  static const MethodChannel _channel = MethodChannel(
    'com.inkpage.reader/word_segmenter',
  );

  /// [text] 中涵蓋 [offset] 的那個詞。原生端不可用時退回單一字元
  /// （surrogate pair 視為一個字）。
  Future<HybridTextRange> wordAt(String text, int offset) async {
    try {
      final result = await _channel.invokeListMethod<int>('wordAt', {
        'text': text,
        'offset': offset,
      });
      if (result != null && result.length == 2) {
        final start = result[0];
        final end = result[1];
        if (0 <= start &&
            start <= offset &&
            offset < end &&
            end <= text.length) {
          return HybridTextRange(start, end);
        }
      }
    } on PlatformException {
      // 落到單字。
    } on MissingPluginException {
      // 非 Android 平台或測試環境。
    }
    return characterAt(text, offset);
  }

  static HybridTextRange characterAt(String text, int offset) {
    var start = offset;
    if (start > 0 &&
        _isLowSurrogate(text.codeUnitAt(start)) &&
        _isHighSurrogate(text.codeUnitAt(start - 1))) {
      start -= 1;
    }
    var end = start + 1;
    if (end < text.length &&
        _isHighSurrogate(text.codeUnitAt(start)) &&
        _isLowSurrogate(text.codeUnitAt(end))) {
      end += 1;
    }
    return HybridTextRange(start, end);
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
}
