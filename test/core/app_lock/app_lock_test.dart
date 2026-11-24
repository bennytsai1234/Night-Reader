import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/app_lock/app_lock.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePlatform implements AppLockPlatform {
  bool deviceSupported = true;
  String? reason = 'away';
  final List<AppLockAuthResult> results = [];
  int prompts = 0;
  Completer<AppLockAuthResult>? pending;
  bool? cover;
  bool? locked;

  @override
  Future<bool> supported() async => deviceSupported;

  @override
  Future<AppLockAuthResult> authenticate() {
    prompts++;
    if (results.isNotEmpty) return Future.value(results.removeAt(0));
    return (pending = Completer<AppLockAuthResult>()).future;
  }

  @override
  Future<String?> leaveReason() async => reason;

  @override
  Future<void> markOwnExcursion() async {}

  @override
  Future<void> configure({required bool cover, required bool locked}) async {
    this.cover = cover;
    this.locked = locked;
  }

  @override
  Future<void> uncover() async {}
}

void main() {
  late _FakePlatform platform;
  late DateTime now;
  late AppLock lock;

  Future<AppLock> start(
    WidgetTester tester, {
    AppLockMode mode = AppLockMode.off,
    bool cover = false,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SharedPreferences.setMockInitialValues({
      PreferKey.appLockMode: mode.name,
      PreferKey.appCoverOnLeave: cover,
    });
    lock = AppLock(platform: platform, clock: () => now)
      ..start(await SharedPreferences.getInstance());
    addTearDown(lock.dispose);
    await tester.pump();
    return lock;
  }

  Future<void> leave(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
  }

  Future<void> comeBack(WidgetTester tester, Duration after) async {
    now = now.add(after);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  AppLockPhase phase() => lock.lockState.value.phase;

  setUp(() {
    platform = _FakePlatform();
    now = DateTime(2026, 11, 24, 21);
  });

  testWidgets('without the lock, leaving and coming back changes nothing', (
    tester,
  ) async {
    await start(tester);
    expect(phase(), AppLockPhase.open);
    await leave(tester);
    expect(phase(), AppLockPhase.open);
    await comeBack(tester, const Duration(hours: 1));
    expect(phase(), AppLockPhase.open);
    expect(platform.prompts, 0);
  });

  testWidgets('opening the app asks to unlock before anything shows', (
    tester,
  ) async {
    final lock = await start(tester, mode: AppLockMode.onLeave);
    expect(platform.prompts, 1);
    expect(phase(), AppLockPhase.authenticating);
    var done = false;
    unawaited(lock.whenOpen().then((_) => done = true));
    platform.pending!.complete(AppLockAuthResult.passed);
    await tester.pump();
    expect(phase(), AppLockPhase.open);
    expect(done, isFalse, reason: 'the entrance waits for the fade-out');
    lock.markOpened();
    await tester.pump();
    expect(done, isTrue);
  });

  testWidgets(
    'leaving with the lock on covers the screen and locks on return',
    (tester) async {
      platform.results.addAll([
        AppLockAuthResult.passed,
        AppLockAuthResult.passed,
      ]);
      await start(tester, mode: AppLockMode.onLeave);
      await leave(tester);
      expect(phase(), AppLockPhase.away);
      expect(platform.locked, isTrue);
      await comeBack(tester, const Duration(seconds: 5));
      expect(platform.prompts, 2);
      expect(phase(), AppLockPhase.open);
    },
  );

  testWidgets(
    'screens 夜讀 opened itself and turning the screen off do not lock',
    (tester) async {
      platform.results.add(AppLockAuthResult.passed);
      await start(tester, mode: AppLockMode.onLeave);
      for (final reason in ['own', 'screenOff']) {
        platform.reason = reason;
        await leave(tester);
        expect(phase(), AppLockPhase.open, reason: reason);
        await comeBack(tester, const Duration(seconds: 30));
        expect(phase(), AppLockPhase.open, reason: reason);
      }
      expect(platform.prompts, 1);
    },
  );

  testWidgets('a browser 夜讀 opened counts only for the leave right after it', (
    tester,
  ) async {
    platform
      ..reason = null
      ..results.addAll([AppLockAuthResult.passed, AppLockAuthResult.passed]);
    await start(tester, mode: AppLockMode.onLeave);
    await lock.markOwnExcursion();
    await leave(tester);
    expect(phase(), AppLockPhase.open);
    await comeBack(tester, const Duration(seconds: 20));
    await leave(tester);
    expect(phase(), AppLockPhase.away, reason: 'the mark was used up');

    await comeBack(tester, const Duration(seconds: 1));
    await lock.markOwnExcursion();
    now = now.add(const Duration(seconds: 10));
    await leave(tester);
    expect(phase(), AppLockPhase.away, reason: 'a stale mark does not count');
  });

  testWidgets('five-minute mode unlocks by itself within five minutes', (
    tester,
  ) async {
    platform.results.addAll([
      AppLockAuthResult.passed,
      AppLockAuthResult.passed,
    ]);
    await start(tester, mode: AppLockMode.afterFiveMinutes);
    await leave(tester);
    expect(phase(), AppLockPhase.away);
    await comeBack(tester, const Duration(minutes: 4));
    expect(phase(), AppLockPhase.open);
    expect(platform.prompts, 1);

    await leave(tester);
    await comeBack(tester, const Duration(minutes: 5));
    expect(platform.prompts, 2);
  });

  testWidgets('five-minute mode locks when the clock went backwards', (
    tester,
  ) async {
    platform.results.add(AppLockAuthResult.passed);
    await start(tester, mode: AppLockMode.afterFiveMinutes);
    await leave(tester);
    await comeBack(tester, const Duration(minutes: -10));
    expect(phase(), AppLockPhase.authenticating);
  });

  testWidgets('losing the window always needs an unlock, even within five '
      'minutes', (tester) async {
    platform.results.add(AppLockAuthResult.passed);
    await start(tester, mode: AppLockMode.afterFiveMinutes);
    await leave(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();
    await comeBack(tester, const Duration(seconds: 3));
    expect(phase(), AppLockPhase.authenticating);
  });

  testWidgets(
    'cancelling keeps it locked with an unlock button that asks again',
    (tester) async {
      platform.results.add(AppLockAuthResult.failed);
      await start(tester, mode: AppLockMode.onLeave);
      expect(
        lock.lockState.value,
        const AppLockState(AppLockPhase.locked, promptFailed: true),
      );
      // 辨識框收掉、焦點回來不會一直跳。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(platform.prompts, 1);

      platform.results.add(AppLockAuthResult.passed);
      await lock.unlock();
      expect(phase(), AppLockPhase.open);
    },
  );

  testWidgets('leaving while the prompt is open asks again on return', (
    tester,
  ) async {
    await start(tester, mode: AppLockMode.onLeave);
    expect(phase(), AppLockPhase.authenticating);
    await leave(tester);
    expect(phase(), AppLockPhase.authenticating);
    platform.pending!.complete(AppLockAuthResult.interrupted);
    await tester.pump();
    expect(phase(), AppLockPhase.locked);
    platform.results.add(AppLockAuthResult.passed);
    await comeBack(tester, const Duration(seconds: 2));
    expect(platform.prompts, 2);
    expect(phase(), AppLockPhase.open);
  });

  testWidgets('a phone without a screen lock never locks', (tester) async {
    platform.deviceSupported = false;
    await start(tester, mode: AppLockMode.onLeave);
    await tester.pump();
    expect(phase(), AppLockPhase.open);
    expect(lock.supported, isFalse);
    await leave(tester);
    expect(phase(), AppLockPhase.open);
  });

  testWidgets('turning the lock on needs one unlock first', (tester) async {
    await start(tester);
    platform.results.add(AppLockAuthResult.failed);
    expect(await lock.setMode(AppLockMode.onLeave), isFalse);
    expect(lock.mode, AppLockMode.off);
    platform.results.add(AppLockAuthResult.passed);
    expect(await lock.setMode(AppLockMode.onLeave), isTrue);
    expect(lock.coverEffective, isTrue);
    expect(platform.cover, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PreferKey.appLockMode), 'onLeave');
    // 換成 5 分鐘、或關掉，不用再辨識。
    expect(await lock.setMode(AppLockMode.afterFiveMinutes), isTrue);
    expect(await lock.setMode(AppLockMode.off), isTrue);
    expect(platform.prompts, 2);
  });

  testWidgets('back does nothing while locked', (tester) async {
    platform.results.add(AppLockAuthResult.failed);
    await start(tester, mode: AppLockMode.onLeave);
    expect(await lock.didPopRoute(), isTrue);
    platform.results.add(AppLockAuthResult.passed);
    await lock.unlock();
    expect(await lock.didPopRoute(), isFalse);
  });
}
