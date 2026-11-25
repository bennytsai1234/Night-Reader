import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/playback/sleep_timer.dart';
import 'package:night_reader/features/reader/features/settings/reader_settings_controller.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_phase.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTts extends ChangeNotifier implements ReaderTtsSheetController {
  _FakeTts(this.phase);

  @override
  ReaderTtsPhase phase;

  int previous = 0;
  int next = 0;

  @override
  late final SleepTimer sleepTimer = SleepTimer(onExpired: () {});

  @override
  bool get canSkipSentence =>
      phase == ReaderTtsPhase.reading || phase == ReaderTtsPhase.paused;

  @override
  double get rate => 1;

  @override
  double get pitch => 1;

  @override
  Future<void> toggle() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> setRate(double value) async {}

  @override
  Future<void> setPitch(double value) async {}

  @override
  Future<void> skipToPreviousSentence() async => previous++;

  @override
  Future<void> skipToNextSentence() async => next++;

  @override
  void dispose() {
    sleepTimer.dispose();
    super.dispose();
  }
}

void main() {
  late ReaderSettingsController settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final getIt = GetIt.instance;
    if (getIt.isRegistered<SharedPreferences>()) {
      getIt.unregister<SharedPreferences>();
    }
    getIt.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    settings = ReaderSettingsController();
  });

  tearDown(() {
    settings.dispose();
    GetIt.instance.reset();
  });

  Future<void> pumpPanel(WidgetTester tester, _FakeTts tts) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReaderTtsPanel(tts: tts, settings: settings),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('上一句、下一句排在播放列下面、結束朗讀上面', (tester) async {
    final tts = _FakeTts(ReaderTtsPhase.reading);
    addTearDown(tts.dispose);
    await pumpPanel(tester, tts);

    final play = tester.getTopLeft(find.text('暫停朗讀')).dy;
    final previous = tester.getTopLeft(find.text('上一句')).dy;
    final next = tester.getTopLeft(find.text('下一句')).dy;
    final stop = tester.getTopLeft(find.text('結束朗讀')).dy;
    expect(previous, greaterThan(play));
    expect(next, greaterThan(previous));
    expect(stop, greaterThan(next));
  });

  testWidgets('朗讀中按上一句、下一句交給控制器', (tester) async {
    final tts = _FakeTts(ReaderTtsPhase.reading);
    addTearDown(tts.dispose);
    await pumpPanel(tester, tts);

    await tester.tap(find.text('上一句'));
    await tester.tap(find.text('下一句'));
    await tester.pump();

    expect(tts.previous, 1);
    expect(tts.next, 1);
  });

  testWidgets('暫停中也能按上一句、下一句', (tester) async {
    final tts = _FakeTts(ReaderTtsPhase.paused);
    addTearDown(tts.dispose);
    await pumpPanel(tester, tts);

    await tester.tap(find.text('上一句'));
    await tester.tap(find.text('下一句'));
    await tester.pump();

    expect(tts.previous, 1);
    expect(tts.next, 1);
  });

  testWidgets('沒在朗讀時上一句、下一句灰著，按了不動', (tester) async {
    final tts = _FakeTts(ReaderTtsPhase.idle);
    addTearDown(tts.dispose);
    await pumpPanel(tester, tts);

    await tester.tap(find.text('上一句'));
    await tester.tap(find.text('下一句'));
    await tester.pump();

    expect(tts.previous, 0);
    expect(tts.next, 0);
  });
}
