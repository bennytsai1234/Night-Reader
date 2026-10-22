import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_controller.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_departure.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_entrance.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

void main() {
  late ReaderV2MenuController menu;
  late ReaderV2MenuDeparture departure;

  /// 閱讀器的下方選單：跟著選單的開關滑進滑出，收完時通知 [departure]。
  Future<void> pumpMenu(WidgetTester tester) async {
    menu = ReaderV2MenuController();
    departure = ReaderV2MenuDeparture(menu);
    addTearDown(() {
      departure.dispose();
      menu.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.bottomCenter,
          child: ReaderV2MenuEntrance(
            visible: menu.controlsVisible,
            edge: AxisDirection.down,
            onHidden: departure.menusHidden,
            child: const SizedBox(width: 100, height: 50),
          ),
        ),
      ),
    );
  }

  Future<void> openMenu(WidgetTester tester) async {
    menu.showControls();
    await tester.pumpAndSettle();
  }

  /// 記下 [ticket] 的結果；還沒結果時是空的。
  List<bool> outcome(ReaderV2MenuDepartureTicket ticket) {
    final results = <bool>[];
    ticket.menusGone.then(results.add);
    return results;
  }

  testWidgets('a request waits until the menu is fully off screen', (
    tester,
  ) async {
    await pumpMenu(tester);
    await openMenu(tester);

    final ticket = departure.depart();
    final result = outcome(ticket);
    expect(menu.controlsVisible.value, isFalse, reason: '開始收起選單');
    await tester.pump(AppMotion.readerMenuOut ~/ 2);
    expect(result, isEmpty, reason: '滑出途中不推頁');
    expect(ticket.canDepart, isFalse);

    await tester.pumpAndSettle();
    expect(result, [true]);
    expect(ticket.canDepart, isTrue);
  });

  testWidgets('with the menu already closed a request goes at once', (
    tester,
  ) async {
    await pumpMenu(tester);
    final ticket = departure.depart();
    final result = outcome(ticket);
    await tester.pump();
    expect(result, [true]);
    expect(ticket.canDepart, isTrue);
  });

  testWidgets('reopening the menu mid-slide drops the request; a later, '
      'unrelated close does not push', (tester) async {
    await pumpMenu(tester);
    await openMenu(tester);

    final ticket = departure.depart();
    final result = outcome(ticket);
    await tester.pump(AppMotion.readerMenuOut ~/ 2);
    // 點正文叫回選單：收起動畫倒回去，永遠不會收完。
    menu.showControls();
    await tester.pumpAndSettle();
    expect(result, [false], reason: '請求作廢，不再等');

    menu.dismissControls();
    await tester.pumpAndSettle();
    expect(result, [false]);
    expect(ticket.canDepart, isFalse, reason: '之後的收起不會放行舊請求');
  });

  testWidgets('choosing another destination drops the first request', (
    tester,
  ) async {
    await pumpMenu(tester);
    await openMenu(tester);

    final first = departure.depart();
    final firstResult = outcome(first);
    await tester.pump(AppMotion.readerMenuOut ~/ 2);
    final second = departure.depart();
    final secondResult = outcome(second);
    await tester.pumpAndSettle();

    expect(firstResult, [false]);
    expect(first.canDepart, isFalse);
    expect(secondResult, [true]);
    expect(second.canDepart, isTrue);
  });

  testWidgets('reopening the menu after it slid out, while the page is still '
      'saving progress, stops the push', (tester) async {
    await pumpMenu(tester);
    await openMenu(tester);

    final ticket = departure.depart();
    final result = outcome(ticket);
    await tester.pumpAndSettle();
    expect(result, [true]);

    // 書籍詳情寫入閱讀進度的期間，選單又被打開。
    menu.showControls();
    await tester.pump();
    expect(ticket.canDepart, isFalse, reason: '推頁前再確認，帶著玻璃不推');
  });

  testWidgets('leaving the reader ends a waiting request', (tester) async {
    await pumpMenu(tester);
    await openMenu(tester);

    final ticket = departure.depart();
    final result = outcome(ticket);
    await tester.pump(AppMotion.readerMenuOut ~/ 2);
    departure.dispose();
    await tester.pump();
    expect(result, [false]);
    expect(ticket.canDepart, isFalse);
    // tearDown 會再 dispose 一次；先換一個新的給它。
    departure = ReaderV2MenuDeparture(menu);
    await tester.pumpAndSettle();
  });
}
