import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/cover_reveal.dart';

void main() {
  testWidgets('slots under a waiting reveal are built one per frame, and '
      'the wait ends only after all of them are', (tester) async {
    final reveal = CoverReveal();
    addTearDown(reveal.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CoverRevealScope(
          notifier: reveal,
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
      reveal.settle(const Duration(milliseconds: 300)).then((_) {
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

  testWidgets('a single slot is still under the wait when it is built, so its '
      'cover holds the reveal', (tester) async {
    final reveal = CoverReveal();
    addTearDown(reveal.dispose);
    bool? waitingWhenBuilt;
    await tester.pumpWidget(
      CoverRevealScope(
        notifier: reveal,
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
      reveal.settle(const Duration(seconds: 5)).then((_) {
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
    final reveal = CoverReveal();
    addTearDown(reveal.dispose);
    // settle 要等一幀畫完。
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(reveal.settle(Duration.zero));
    await tester.pump();
    await tester.pump();
    expect(reveal.waiting, isFalse);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CoverRevealScope(
          notifier: reveal,
          child: const CoverRevealSlot(child: Text('書')),
        ),
      ),
    );
    expect(find.text('書'), findsOneWidget);
  });
}
