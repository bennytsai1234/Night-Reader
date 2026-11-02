import 'dart:convert';

import 'package:night_reader/core/models/book.dart';

import 'reader_v2_location.dart';

enum ReaderV2OpenIntent { resume, chapterStart }

class ReaderV2OpenTarget {
  const ReaderV2OpenTarget({
    required this.location,
    required this.intent,
    this.chapterTitle,
  });

  final ReaderV2Location location;
  final ReaderV2OpenIntent intent;

  /// 要開的那一章的章名（書籤）：開書時目錄可能還沒抓（剛還原、剛同步來
  /// 的書），[location] 的章節序號只是別處的座標；閱讀器讀到目錄後照章名
  /// 再對一次（`ReaderV2Runtime.openBook`）。
  final String? chapterTitle;

  factory ReaderV2OpenTarget.resume(Book book) {
    ReaderV2Location? persistedAnchor;
    final encoded = book.readerAnchorJson;
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) {
          persistedAnchor = ReaderV2Location.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      } on FormatException {
        // Corrupt persisted JSON is external data. Scalar progress remains the
        // portable fallback; unrelated programming errors must stay visible.
      }
    }
    final scalar = ReaderV2Location(
      chapterIndex: book.chapterIndex,
      charOffset: book.charOffset,
      visualOffsetPx: book.visualOffsetPx,
    ).normalized();
    final anchor = persistedAnchor;
    return ReaderV2OpenTarget(
      intent: ReaderV2OpenIntent.resume,
      // The DB writes scalar progress and readerAnchorJson atomically. If an
      // older/imported row disagrees, the scalar coordinates are the chapter
      // ownership truth; stale anchor metadata must not redirect another
      // chapter.
      location:
          anchor != null &&
              anchor.chapterIndex == scalar.chapterIndex &&
              anchor.charOffset == scalar.charOffset
          ? anchor.copyWith(visualOffsetPx: scalar.visualOffsetPx)
          : scalar,
    );
  }

  factory ReaderV2OpenTarget.chapterStart(int chapterIndex) {
    return ReaderV2OpenTarget(
      intent: ReaderV2OpenIntent.chapterStart,
      location: ReaderV2Location(
        chapterIndex: chapterIndex,
        charOffset: 0,
      ).normalized(),
    );
  }

  factory ReaderV2OpenTarget.location(
    ReaderV2Location location, {
    ReaderV2OpenIntent intent = ReaderV2OpenIntent.chapterStart,
    String? chapterTitle,
  }) {
    return ReaderV2OpenTarget(
      intent: intent,
      location: location.normalized(),
      chapterTitle: chapterTitle,
    );
  }
}
