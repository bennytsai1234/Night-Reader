import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/app_lock/app_lock.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_lock_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePlatform implements AppLockPlatform {
  final List<AppLockAuthResult> results = [];
  Completer<AppLockAuthResult>? pending;

  @override
  Future<bool> supported() async => true;

  @override
  Future<AppLockAuthResult> authenticate() {
    if (results.isNotEmpty) return Future.value(results.removeAt(0));
    return (pending = Completer<AppLockAuthResult>()).future;
  }

  @override
  Future<String?> leaveReason() async => 'away';

  @override
  Future<void> markOwnExcursion() async {}

  @override
  Future<void> clearOwnExcursion() async {}

  @override
  Future<void> configure({required bool cover, required bool locked}) async {}

  @override
  Future<void> uncover() async {}
}

void main() {
  late _FakePlatform platform;
  late AppLock lock;
  final navigatorKey = GlobalKey<NavigatorState>();
  var tapped = 0;

  Future<void> pumpApp(WidgetTester tester, {required AppLockMode mode}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SharedPreferences.setMockInitialValues({PreferKey.appLockMode: mode.name});
    platform = _FakePlatform();
    // 和 main 一樣在 App 之前開始，返回鍵先問到鎖。
    lock = AppLock(platform: platform)
      ..start(await SharedPreferences.getInstance());
    addTearDown(lock.dispose);
    tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => AppLockScope(lock: lock, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => tapped++,
                child: const Text('書架'),
              ),
            ),
          ),
        ),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('閱讀器'))),
      ),
    );
    await tester.pump();
  }

  testWidgets('while locked, back keeps the page underneath and taps do not '
      'reach it', (tester) async {
    await pumpApp(tester, mode: AppLockMode.onLeave);
    platform.pending!.complete(AppLockAuthResult.failed);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(navigatorKey.currentState!.canPop(), isTrue);

    // 底下的頁面不收點擊。
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('書架'), warnIfMissed: false);
    expect(tapped, 0);
  });

  testWidgets('after cancelling, the unlock button asks again and the lock '
      'screen fades out', (tester) async {
    await pumpApp(tester, mode: AppLockMode.onLeave);
    platform.pending!.complete(AppLockAuthResult.failed);
    await tester.pumpAndSettle();

    platform.results.add(AppLockAuthResult.passed);
    await tester.tap(find.text('解鎖'));
    await tester.pump();
    expect(lock.lockState.value.phase, AppLockPhase.open);
    var opened = false;
    unawaited(lock.whenOpen().then((_) => opened = true));

    // 淡出中：鎖的畫面還在，進場還沒開始。
    await tester.pump(AppMotion.fade ~/ 2);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(opened, isFalse);

    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    expect(opened, isTrue);
    expect(find.text('閱讀器'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('書架'), findsOneWidget);
  });

  testWidgets('without the lock nothing covers the app', (tester) async {
    await pumpApp(tester, mode: AppLockMode.off);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    expect(await lock.whenOpen().then((_) => true), isTrue);
  });
}
