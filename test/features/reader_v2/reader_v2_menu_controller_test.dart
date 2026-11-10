// 拖動章內進度的狀態：放開後拖動條停在選定的位置，只有同一次拖動的跳轉
// 做完才改回跟閱讀進度。

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_controller.dart';

void main() {
  late ReaderV2MenuController menu;
  setUp(() => menu = ReaderV2MenuController());
  tearDown(() => menu.dispose());

  test('放開後停在選定的位置，這一次的跳轉做完才放手', () {
    menu
      ..onScrubStart(20)
      ..onScrubbing(30);
    final drag = menu.onScrubEnd(30);
    expect(menu.scrub.value, (
      isScrubbing: false,
      holdsSlider: true,
      percent: 30,
    ));

    menu.onScrubSettled(drag);
    expect(menu.scrub.value.holdsSlider, isFalse);
  });

  test('連續放開兩次，先做完的舊跳轉不解除新一次的停留', () {
    menu.onScrubStart(20);
    final first = menu.onScrubEnd(20);
    menu.onScrubStart(80);
    final second = menu.onScrubEnd(80);

    menu.onScrubSettled(first);
    expect(menu.scrub.value, (
      isScrubbing: false,
      holdsSlider: true,
      percent: 80,
    ));

    menu.onScrubSettled(second);
    expect(menu.scrub.value.holdsSlider, isFalse);
  });

  test('舊的跳轉做完時又在拖，不打斷拖動', () {
    menu.onScrubStart(20);
    final first = menu.onScrubEnd(20);
    menu.onScrubStart(50);

    menu.onScrubSettled(first);
    expect(menu.scrub.value, (
      isScrubbing: true,
      holdsSlider: true,
      percent: 50,
    ));
  });
}
