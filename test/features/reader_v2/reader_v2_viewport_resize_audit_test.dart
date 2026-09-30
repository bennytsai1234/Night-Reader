import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page_shell.dart';

void main() {
  testWidgets(
    'system inset resize moves the viewport rect but keeps scroll pixels stable',
    (tester) async {
      final controller = ScrollController(keepScrollOffset: false);
      addTearDown(controller.dispose);
      final markerKey = GlobalKey();

      Future<({double pixels, double viewportTop, double markerY})> pump(
        double topInset,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(360, 640),
                padding: EdgeInsets.only(top: topInset),
              ),
              child: Scaffold(
                body: _ViewportHarness(
                  controller: controller,
                  markerKey: markerKey,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        if (controller.hasClients && controller.offset == 0) {
          controller.jumpTo(200);
          await tester.pump();
        }

        final viewportTop = tester
            .getTopLeft(find.byKey(_viewportKey))
            .dy;
        final markerY = tester.getTopLeft(find.byKey(markerKey)).dy;
        return (
          pixels: controller.position.pixels,
          viewportTop: viewportTop,
          markerY: markerY,
        );
      }

      final before = await pump(24);
      final during = await pump(0);
      final after = await pump(24);

      expect(before.pixels, 200);
      expect(during.pixels, before.pixels);
      expect(after.pixels, before.pixels);

      expect(before.viewportTop, 24);
      expect(during.viewportTop, 0);
      expect(after.viewportTop, 24);

      expect(during.markerY, closeTo(before.markerY - 24, 0.01));
      expect(after.markerY, closeTo(before.markerY, 0.01));
    },
  );
}

const _viewportKey = ValueKey<String>('reader-viewport');

class _ViewportHarness extends StatelessWidget {
  const _ViewportHarness({
    required this.controller,
    required this.markerKey,
  });

  final ScrollController controller;
  final GlobalKey markerKey;

  @override
  Widget build(BuildContext context) {
    final layout = ReaderV2PageChromeLayout.resolve(
      mediaPadding: MediaQuery.paddingOf(context),
      hideStatusBar: false,
      showHeaderInfo: false,
      showFooterInfo: false,
      paddingTop: 0,
      paddingBottom: 0,
    );

    return Stack(
      children: [
        Positioned.fill(
          key: _viewportKey,
          top: layout.contentTop,
          bottom: layout.contentBottom,
          child: SingleChildScrollView(
            controller: controller,
            child: Column(
              children: [
                const SizedBox(height: 300),
                SizedBox(key: markerKey, height: 20),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
