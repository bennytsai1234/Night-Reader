import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/source/explore_kind.dart';
import 'package:night_reader/features/explore/widgets/legado_explore_kind_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildHarness(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 200, child: child),
        ),
      ),
    );
  }

  testWidgets('wrapBefore starts a new row', (tester) async {
    const firstKey = Key('first');
    const secondKey = Key('second');

    await tester.pumpWidget(
      buildHarness(
        const LegadoExploreKindFlow(
          styles: <FlexChildStyle>[
            FlexChildStyle(),
            FlexChildStyle(layoutWrapBefore: true),
          ],
          children: <Widget>[
            SizedBox(key: firstKey, width: 70, height: 20),
            SizedBox(key: secondKey, width: 70, height: 20),
          ],
        ),
      ),
    );

    final firstOffset = tester.getTopLeft(find.byKey(firstKey));
    final secondOffset = tester.getTopLeft(find.byKey(secondKey));

    expect(secondOffset.dy, greaterThan(firstOffset.dy));
    expect(secondOffset.dx, 0);
  });

  testWidgets('flexBasisPercent splits children into equal columns', (
    tester,
  ) async {
    const firstKey = Key('first');
    const secondKey = Key('second');

    await tester.pumpWidget(
      buildHarness(
        const LegadoExploreKindFlow(
          styles: <FlexChildStyle>[
            FlexChildStyle(layoutFlexBasisPercent: 0.5),
            FlexChildStyle(layoutFlexBasisPercent: 0.5),
          ],
          children: <Widget>[
            SizedBox(key: firstKey, height: 20),
            SizedBox(key: secondKey, height: 20),
          ],
        ),
      ),
    );

    final firstSize = tester.getSize(find.byKey(firstKey));
    final secondOffset = tester.getTopLeft(find.byKey(secondKey));

    expect(firstSize.width, closeTo(96, 0.1));
    expect(secondOffset.dx, closeTo(104, 0.1));
    expect(secondOffset.dy, 0);
  });
}
