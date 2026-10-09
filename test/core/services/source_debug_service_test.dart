import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/source_debug_service.dart';

void main() {
  test('logs from a cancelled run never reach the next run', () async {
    final service = SourceDebugService();
    final messages = <String>[];
    final sub = service.logStream.listen((log) => messages.add(log.message));
    addTearDown(sub.cancel);

    // 第一輪沒有搜尋網址，會在網路層失敗；不等它結束就取消並開始第二輪。
    final source = BookSource(
      bookSourceUrl: 'https://a.invalid',
      bookSourceName: '甲',
    );
    final first = service.startDebug(source, '關鍵字');
    service.cancel();
    final second = service.startDebug(
      BookSource(bookSourceUrl: 'https://b.invalid', bookSourceName: '乙'),
      '關鍵字',
    );
    await Future.wait([first, second]);

    await Future<void>.delayed(Duration.zero);
    final secondStart = messages.indexOf('⇒開始調試書源: 乙');
    expect(secondStart, isNonNegative);
    // 第一輪取消後才回來的錯誤不會混進第二輪。
    expect(
      messages.skip(secondStart).where((m) => m.startsWith('❌')),
      hasLength(1),
    );
  });
}
