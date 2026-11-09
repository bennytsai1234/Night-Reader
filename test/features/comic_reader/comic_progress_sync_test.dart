import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/comic_reader/comic_progress_sync.dart';
import 'package:night_reader/features/comic_reader/comic_strip_view.dart';

void main() {
  test('另一台在同一話差 1 張以內不跳，換話或差更多才跳', () {
    const here = ComicLocation(3, 10, fraction: 0.4);
    expect(ComicProgressSync.shouldJump(here, 3, 10), isFalse);
    expect(ComicProgressSync.shouldJump(here, 3, 11), isFalse);
    expect(ComicProgressSync.shouldJump(here, 3, 9), isFalse);
    expect(ComicProgressSync.shouldJump(here, 3, 12), isTrue);
    expect(ComicProgressSync.shouldJump(here, 4, 10), isTrue);
  });
}
