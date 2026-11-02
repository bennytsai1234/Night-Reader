import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/layout/tablet_text_scale.dart';

void main() {
  Future<double> scaledAt(
    WidgetTester tester,
    Size size, {
    TextScaler system = TextScaler.noScaling,
  }) async {
    late double scaled;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, textScaler: system),
        child: TabletTextScale(
          child: Builder(
            builder: (context) {
              scaled = MediaQuery.textScalerOf(context).scale(15);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return scaled;
  }

  testWidgets('phones keep the system text size', (tester) async {
    expect(await scaledAt(tester, const Size(412, 915)), 15);
    // 手機橫拿：短邊還是手機。
    expect(await scaledAt(tester, const Size(915, 412)), 15);
  });

  testWidgets('tablets enlarge text 1.2 times in either orientation', (
    tester,
  ) async {
    expect(await scaledAt(tester, const Size(1280, 880)), closeTo(18, 1e-9));
    expect(await scaledAt(tester, const Size(880, 1280)), closeTo(18, 1e-9));
  });

  testWidgets('the tablet enlargement stacks on the system text size', (
    tester,
  ) async {
    final scaled = await scaledAt(
      tester,
      const Size(1280, 880),
      system: const TextScaler.linear(1.3),
    );
    expect(scaled, closeTo(15 * 1.3 * 1.2, 1e-9));
  });
}
