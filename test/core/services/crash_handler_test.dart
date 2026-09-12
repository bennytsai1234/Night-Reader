import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/crash_handler.dart';

void main() {
  setUp(CrashHandler.resetErrorDeduplicationForTesting);
  tearDown(CrashHandler.resetErrorDeduplicationForTesting);

  test('相同錯誤在短時間內只允許記錄一次', () {
    final first = DateTime.utc(2026, 9, 12, 15, 13, 39);
    final stack = StackTrace.fromString('same stack');

    expect(
      CrashHandler.shouldRecordErrorForTesting(
        'Null check operator used on a null value',
        stack,
        now: first,
      ),
      isTrue,
    );
    expect(
      CrashHandler.shouldRecordErrorForTesting(
        'Null check operator used on a null value',
        stack,
        now: first.add(const Duration(milliseconds: 500)),
      ),
      isFalse,
    );
  });

  test('相同錯誤在窗口外或堆疊不同時仍會記錄', () {
    final first = DateTime.utc(2026, 9, 12, 15, 13, 39);

    expect(
      CrashHandler.shouldRecordErrorForTesting(
        'Null check operator used on a null value',
        StackTrace.fromString('stack A'),
        now: first,
      ),
      isTrue,
    );
    expect(
      CrashHandler.shouldRecordErrorForTesting(
        'Null check operator used on a null value',
        StackTrace.fromString('stack A'),
        now: first.add(const Duration(seconds: 3)),
      ),
      isTrue,
    );
    expect(
      CrashHandler.shouldRecordErrorForTesting(
        'Null check operator used on a null value',
        StackTrace.fromString('stack B'),
        now: first.add(const Duration(seconds: 3)),
      ),
      isTrue,
    );
  });
}
