import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/bookmark.dart';

import 'reader_v2_location.dart';

enum ReaderV2OpenIntent { resume, chapterStart, bookmark }

class ReaderV2OpenTarget {
  const ReaderV2OpenTarget({required this.location, required this.intent});

  final ReaderV2Location location;
  final ReaderV2OpenIntent intent;

  factory ReaderV2OpenTarget.resume(Book book) {
    return ReaderV2OpenTarget(
      intent: ReaderV2OpenIntent.resume,
      location:
          ReaderV2Location(
            chapterIndex: book.chapterIndex,
            charOffset: book.charOffset,
            visualOffsetPx: book.visualOffsetPx,
          ).normalized(),
    );
  }

  factory ReaderV2OpenTarget.chapterStart(int chapterIndex) {
    return ReaderV2OpenTarget(
      intent: ReaderV2OpenIntent.chapterStart,
      location:
          ReaderV2Location(
            chapterIndex: chapterIndex,
            charOffset: 0,
          ).normalized(),
    );
  }

  factory ReaderV2OpenTarget.bookmark(Bookmark bookmark) {
    return ReaderV2OpenTarget(
      intent: ReaderV2OpenIntent.bookmark,
      location:
          ReaderV2Location(
            chapterIndex: bookmark.chapterIndex,
            charOffset: bookmark.chapterPos,
          ).normalized(),
    );
  }

  factory ReaderV2OpenTarget.location(
    ReaderV2Location location, {
    ReaderV2OpenIntent intent = ReaderV2OpenIntent.chapterStart,
  }) {
    return ReaderV2OpenTarget(intent: intent, location: location.normalized());
  }
}
