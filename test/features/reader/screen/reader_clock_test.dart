import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader/screen/reader_page_shell.dart';

void main() {
  test('頁首頁尾的時間照實際經過的時間排到下一個整分', () {
    // 紐約 2026-11-01 第一次的 01:59:30（夏令時間，05:59:30Z）；02:00 撥回
    // 01:00，下一分是 30 秒後，不是一小時後。
    final beforeFallBack = DateTime.utc(2026, 11, 1, 5, 59, 30);
    expect(untilNextClockMinute(beforeFallBack), const Duration(seconds: 30));
    expect(
      untilNextClockMinute(beforeFallBack.toLocal()),
      const Duration(seconds: 30),
    );
    expect(
      untilNextClockMinute(DateTime(2026, 12, 31, 23, 59, 59, 250)),
      const Duration(milliseconds: 750),
    );
    expect(
      untilNextClockMinute(DateTime(2026, 3, 1, 8, 0)),
      const Duration(minutes: 1),
    );
  });
}
