import 'dart:convert';

import 'package:night_reader/core/models/book.dart';

import 'reader_location.dart';

enum ReaderOpenIntent { resume, chapterStart }

class ReaderOpenTarget {
  const ReaderOpenTarget({
    required this.location,
    required this.intent,
    this.chapterTitle,
  });

  final ReaderLocation location;
  final ReaderOpenIntent intent;

  /// 要開的那一章的章名（書籤）：開書時目錄可能還沒抓（剛還原、剛同步來
  /// 的書），[location] 的章節序號只是別處的座標；閱讀器讀到目錄後照章名
  /// 再對一次（`ReaderRuntime.openBook`）。
  final String? chapterTitle;

  factory ReaderOpenTarget.resume(Book book) {
    ReaderLocation? persistedAnchor;
    final encoded = book.readerAnchorJson;
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) {
          persistedAnchor = ReaderLocation.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      } on FormatException {
        // Corrupt persisted JSON is external data. Scalar progress remains the
        // portable fallback; unrelated programming errors must stay visible.
      }
    }
    final scalar = ReaderLocation(
      chapterIndex: book.chapterIndex,
      charOffset: book.charOffset,
      visualOffsetPx: book.visualOffsetPx,
    ).normalized();
    final anchor = persistedAnchor;
    return ReaderOpenTarget(
      intent: ReaderOpenIntent.resume,
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

  factory ReaderOpenTarget.chapterStart(int chapterIndex) {
    return ReaderOpenTarget(
      intent: ReaderOpenIntent.chapterStart,
      location: ReaderLocation(
        chapterIndex: chapterIndex,
        charOffset: 0,
      ).normalized(),
    );
  }

  factory ReaderOpenTarget.location(
    ReaderLocation location, {
    ReaderOpenIntent intent = ReaderOpenIntent.chapterStart,
    String? chapterTitle,
  }) {
    return ReaderOpenTarget(
      intent: intent,
      location: location.normalized(),
      chapterTitle: chapterTitle,
    );
  }
}
