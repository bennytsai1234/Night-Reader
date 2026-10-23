import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/cover_reveal.dart';

void main() {
  testWidgets('slots under a waiting reveal are built one per frame, and '
      'the wait ends only after all of them are', (tester) async {
    final reveal = CoverReveal(CoverWait.onDevice);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CoverRevealScope(
          reveal: reveal,
          child: Column(
            children: [
              for (var i = 0; i < 3; i++)
                CoverRevealSlot(
                  placeholder: const SizedBox(height: 10),
                  child: SizedBox(height: 10, child: Text('書$i')),
                ),
            ],
          ),
        ),
      ),
    );
    var settled = false;
    unawaited(
      reveal.settle().then((_) {
        settled = true;
      }),
    );

    expect(find.textContaining('書'), findsNothing, reason: '第一幀只佔位置');
    for (var built = 1; built <= 3; built++) {
      await tester.pump();
      expect(find.textContaining('書'), findsNWidgets(built));
      // 最後一張建好的那一幀畫完才結束等待（它的封面在這一幀登記）。
      if (built < 3) expect(reveal.waiting, isTrue);
    }
    await tester.pump();
    expect(settled, isTrue);
    expect(reveal.waiting, isFalse);
  });

  testWidgets('slots nested in a slot are waited for too: the outer slot '
      'being built does not end the wait before the inner ones are', (
    tester,
  ) async {
    final reveal = CoverReveal(CoverWait.onDevice);
    // 和換場一樣，外層排進來的那一幀就開始等。
    var settled = false;
    unawaited(
      reveal.settle().then((_) {
        settled = true;
      }),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CoverRevealScope(
          reveal: reveal,
          child: CoverRevealSlot(
            child: Column(
              children: [
                for (var i = 0; i < 2; i++)
                  CoverRevealSlot(
                    placeholder: const SizedBox(height: 10),
                    child: SizedBox(height: 10, child: Text('書$i')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // 外層建好的那一幀，裡面的兩塊才排進來。
    await tester.pump();
    expect(find.textContaining('書'), findsNothing);
    expect(settled, isFalse);
    expect(reveal.waiting, isTrue);
    for (var built = 1; built <= 2; built++) {
      await tester.pump();
      expect(find.textContaining('書'), findsNWidgets(built));
    }
    await tester.pump();
    expect(settled, isTrue);
  });

  testWidgets('an unpaced reveal builds every slot, nested ones too, in the '
      'first frame, and still waits for their covers', (tester) async {
    // 開 App 的書架在骨架收住呼吸、畫面靜止後才準備：一次建好，不分幀。
    final reveal = CoverReveal(CoverWait.onDevice, paced: false);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CoverRevealScope(
          reveal: reveal,
          child: CoverRevealSlot(
            child: Column(
              children: [
                for (var i = 0; i < 3; i++)
                  CoverRevealSlot(
                    placeholder: const SizedBox(height: 10),
                    child: Builder(
                      builder: (context) {
                        // 像封面：建的時候還在等待中就登記。
                        CoverRevealScope.waitingOf(context)?.add('封面$i');
                        return SizedBox(height: 10, child: Text('書$i'));
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('書'), findsNWidgets(3), reason: '第一幀全部建好');

    var settled = false;
    unawaited(reveal.settle().then((_) => settled = true));
    await tester.pump();
    expect(settled, isFalse, reason: '封面還沒好');
    for (var i = 0; i < 3; i++) {
      reveal.remove('封面$i');
    }
    await tester.pump();
    expect(settled, isTrue);
  });

  testWidgets('a single slot is still under the wait when it is built, so its '
      'cover holds the reveal', (tester) async {
    final reveal = CoverReveal(CoverWait.onDevice);
    bool? waitingWhenBuilt;
    await tester.pumpWidget(
      CoverRevealScope(
        reveal: reveal,
        child: CoverRevealSlot(
          child: Builder(
            builder: (context) {
              // 像封面：建的時候還在等待中就登記，解碼好才拿掉。
              final waiting = CoverRevealScope.waitingOf(context);
              waitingWhenBuilt ??= waiting != null;
              waiting?.add('cover');
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    var settled = false;
    unawaited(
      reveal.settle().then((_) {
        settled = true;
      }),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(waitingWhenBuilt, isTrue);
    expect(settled, isFalse, reason: '封面還沒好，也還沒逾時');
    reveal.remove('cover');
    await tester.pump();
    expect(settled, isTrue);
  });

  testWidgets('a slot built after the wait ends is built right away', (
    tester,
  ) async {
    final reveal = CoverReveal(CoverWait.onDevice);
    // settle 要等一幀畫完。
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(reveal.settle());
    await tester.pump();
    await tester.pump();
    expect(reveal.waiting, isFalse);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CoverRevealScope(
          reveal: reveal,
          child: const CoverRevealSlot(child: Text('書')),
        ),
      ),
    );
    expect(find.text('書'), findsOneWidget);
  });
}
