import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/playback/sleep_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 19, 23);

  SleepTimer timer() {
    final created = SleepTimer(onExpired: () {}, now: () => now);
    addTearDown(created.dispose);
    return created;
  }

  // 朗讀與有聲書各有一個定時，選項共用（ADR 0055）。有聲書播放器常駐，原本只在
  // 第一次開書時讀偏好：在朗讀面板改成關閉後，有聲書照舊用 30 分。
  test('a choice made on one timer reaches the other live timers', () async {
    SharedPreferences.setMockInitialValues({PreferKey.ttsTimer: 30});
    final audiobook = timer();
    final reader = timer();
    await audiobook.load();
    await reader.load();
    audiobook.sync(active: true, running: true);
    expect(audiobook.remaining, const Duration(minutes: 30));

    await reader.choose(SleepTimerOption.off);
    expect(audiobook.option, SleepTimerOption.off);
    expect(audiobook.remaining, isNull);

    await reader.choose(SleepTimerOption.minutes45);
    expect(audiobook.remaining, const Duration(minutes: 45));

    await reader.choose(SleepTimerOption.custom);
    await reader.setCustomMinutes(20);
    expect(audiobook.customMinutes, 20);
    expect(audiobook.remaining, const Duration(minutes: 20));
  });

  // 開閱讀器時套用存過的朗讀語言較慢，朗讀可能在偏好讀完前就開始。
  test(
    'reading started before the saved timer loaded still counts down',
    () async {
      SharedPreferences.setMockInitialValues({PreferKey.ttsTimer: 45});
      final reader = timer();
      reader.sync(active: true, running: true);
      expect(reader.remaining, isNull);

      await reader.load();
      expect(reader.remaining, const Duration(minutes: 45));
    },
  );
}
