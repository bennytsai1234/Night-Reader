import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/sync/reading_upload_pacer.dart';

void main() {
  late int uploads;
  late bool busy;
  late ReadingUploadPacer pacer;

  /// 計時器要在假時間裡建；測完收掉，不留著計時器。
  void pacerTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      uploads = 0;
      busy = false;
      pacer = ReadingUploadPacer(upload: () => uploads++, busy: () => busy)
        ..start();
      await body(tester);
      pacer.dispose();
    });
  }

  pacerTest('a move is sent once the screen has stood still for 8 seconds', (
    tester,
  ) async {
    pacer.moved();
    await tester.pump(const Duration(seconds: 7));
    expect(uploads, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(uploads, 1);

    // 沒再動就不再送。
    await tester.pump(const Duration(minutes: 1));
    expect(uploads, 1);
  });

  pacerTest('nothing moved: nothing is sent, scrolling alone does not '
      'count', (tester) async {
    pacer.activity();
    await tester.pump(const Duration(seconds: 30));
    expect(uploads, 0);
  });

  pacerTest('scrolling without a saved move still restarts the count', (
    tester,
  ) async {
    pacer.moved();
    await tester.pump(const Duration(seconds: 5));
    pacer.activity();
    await tester.pump(const Duration(seconds: 3));
    expect(uploads, 0);
    await tester.pump(const Duration(seconds: 8));
    expect(uploads, 1);
  });

  pacerTest('auto scrolling keeps moving: nothing is sent until it stops', (
    tester,
  ) async {
    for (var i = 0; i < 30; i++) {
      // 捲動中記下位置，存好時才知道移動了。
      pacer.activity();
      pacer.moved();
      await tester.pump(const Duration(seconds: 2));
    }
    expect(uploads, 0);
    await tester.pump(const Duration(seconds: 8));
    expect(uploads, 1);
  });

  pacerTest('stopping again within 30 seconds sends once more when the 30 '
      'seconds are up', (tester) async {
    pacer.moved();
    await tester.pump(const Duration(seconds: 8));
    expect(uploads, 1);

    pacer.moved();
    await tester.pump(const Duration(seconds: 8));
    expect(uploads, 1, reason: '離上次不到 30 秒');
    pacer.moved();
    await tester.pump(const Duration(seconds: 8));
    expect(uploads, 1);
    // 第 8 秒送的，第 38 秒才滿 30 秒。
    await tester.pump(const Duration(seconds: 13));
    expect(uploads, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(uploads, 2, reason: '到 30 秒時補送一次');
    await tester.pump(const Duration(minutes: 1));
    expect(uploads, 2);
  });

  pacerTest('moving again right before the 30 seconds are up waits for the '
      'screen to stand still', (tester) async {
    pacer.moved();
    await tester.pump(const Duration(seconds: 8));
    pacer.moved();
    await tester.pump(const Duration(seconds: 8));
    // 第 16 秒停住，該在第 38 秒補送；第 37 秒又捲了一下。
    await tester.pump(const Duration(seconds: 21));
    pacer.activity();
    await tester.pump(const Duration(seconds: 1));
    expect(uploads, 1, reason: '捲動途中不送');
    await tester.pump(const Duration(seconds: 7));
    expect(uploads, 1, reason: '從第 38 秒重新數');
    await tester.pump(const Duration(seconds: 1));
    expect(uploads, 2);
  });

  pacerTest('a jump still under way when the 8 seconds are up is waited '
      'for', (tester) async {
    pacer.moved();
    busy = true;
    await tester.pump(const Duration(seconds: 8));
    expect(uploads, 0);
    busy = false;
    await tester.pump(const Duration(seconds: 8));
    expect(uploads, 1);
  });

  pacerTest('going to the background or closing the reader cancels the '
      'wait', (tester) async {
    pacer.moved();
    pacer.stop();
    await tester.pump(const Duration(seconds: 10));
    expect(uploads, 0);
    pacer.moved();
    await tester.pump(const Duration(seconds: 10));
    expect(uploads, 0, reason: '停了之後的移動不算');

    pacer.start();
    pacer.moved();
    await tester.pump(const Duration(seconds: 8));
    expect(uploads, 1);
  });
}
