import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/navigation/status_bar.dart';

void main() {
  group('StatusBarPolicy', () {
    late List<MethodCall> visibilityCalls;
    late GlobalKey<NavigatorState> navigatorKey;

    Future<void> pumpApp(WidgetTester tester) async {
      visibilityCalls = <MethodCall>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method.startsWith('SystemChrome.setEnabledSystemUI')) {
          visibilityCalls.add(call);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [StatusBarPolicy()],
          home: const Scaffold(body: Text('書架')),
        ),
      );
    }

    /// 依最後一次可見性設定判斷；沒設定過就是 App 啟動時的顯示狀態。
    bool statusBarHidden() {
      if (visibilityCalls.isEmpty) return false;
      final last = visibilityCalls.last;
      return last.method == 'SystemChrome.setEnabledSystemUIOverlays' &&
          !(last.arguments as List<Object?>).contains('SystemUiOverlay.top');
    }

    Route<void> readerRoute({Widget? page}) => PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) =>
          page ??
          const StatusBarHidden(
            hidden: true,
            child: Scaffold(body: Text('閱讀')),
          ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );

    Route<void> plainPage(String label) =>
        MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(label)));

    /// 模擬使用者從頂端下滑叫出狀態列。
    void revealStatusBar(WidgetTester tester) {
      unawaited(
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.platform.name,
          SystemChannels.platform.codec.encodeMethodCall(
            const MethodCall('SystemChrome.systemUIChange', <Object>[true]),
          ),
          (_) {},
        ),
      );
    }

    testWidgets('開啟閱讀頁時收起狀態列；一開始返回就顯示，不等返回動畫結束', (tester) async {
      await pumpApp(tester);

      unawaited(navigatorKey.currentState!.push(readerRoute()));
      await tester.pump();
      expect(statusBarHidden(), isTrue);
      await tester.pumpAndSettle();

      navigatorKey.currentState!.pop();
      await tester.pump();
      expect(find.text('閱讀'), findsOneWidget, reason: '返回動畫仍在進行');
      expect(statusBarHidden(), isFalse);
      await tester.pumpAndSettle();
      expect(statusBarHidden(), isFalse);
    });

    testWidgets('從閱讀頁開啟一般頁面時顯示狀態列，回到閱讀頁再收起', (tester) async {
      await pumpApp(tester);
      unawaited(navigatorKey.currentState!.push(readerRoute()));
      await tester.pumpAndSettle();

      unawaited(navigatorKey.currentState!.push(plainPage('全域系統設定')));
      await tester.pump();
      expect(statusBarHidden(), isFalse);
      await tester.pumpAndSettle();

      navigatorKey.currentState!.pop();
      await tester.pump();
      expect(statusBarHidden(), isTrue);
    });

    testWidgets('面板蓋在閱讀頁上時維持隱藏；從面板開啟的整頁頁面顯示狀態列', (tester) async {
      await pumpApp(tester);
      unawaited(navigatorKey.currentState!.push(readerRoute()));
      await tester.pumpAndSettle();

      unawaited(
        showModalBottomSheet<void>(
          context: tester.element(find.text('閱讀')),
          builder: (_) => const Text('替換規則面板'),
        ),
      );
      await tester.pumpAndSettle();
      expect(statusBarHidden(), isTrue);

      unawaited(
        Navigator.of(tester.element(find.text('替換規則面板')))
            .push(plainPage('管理規則')),
      );
      await tester.pump();
      expect(statusBarHidden(), isFalse);
      await tester.pumpAndSettle();

      Navigator.of(tester.element(find.text('管理規則'))).pop();
      await tester.pump();
      expect(statusBarHidden(), isTrue);
    });

    testWidgets('換源改開另一個閱讀頁時，狀態列全程保持隱藏', (tester) async {
      await pumpApp(tester);
      unawaited(navigatorKey.currentState!.push(readerRoute()));
      await tester.pumpAndSettle();
      final callsBefore = visibilityCalls.length;

      unawaited(navigatorKey.currentState!.pushReplacement(readerRoute()));
      await tester.pumpAndSettle();

      expect(visibilityCalls.skip(callsBefore), isEmpty);
      expect(statusBarHidden(), isTrue);
    });

    testWidgets('閱讀頁關閉隱藏設定時立即顯示狀態列', (tester) async {
      await pumpApp(tester);
      var hidden = true;
      late StateSetter setPageState;
      unawaited(
        navigatorKey.currentState!.push(
          readerRoute(
            page: StatefulBuilder(
              builder: (context, setState) {
                setPageState = setState;
                return StatusBarHidden(
                  hidden: hidden,
                  child: const Scaffold(body: Text('閱讀')),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(statusBarHidden(), isTrue);

      setPageState(() => hidden = false);
      await tester.pump();
      expect(statusBarHidden(), isFalse);
    });

    testWidgets('下滑叫出狀態列後 3 秒收回；已離開閱讀頁則不收回', (tester) async {
      await pumpApp(tester);
      unawaited(navigatorKey.currentState!.push(readerRoute()));
      await tester.pumpAndSettle();

      revealStatusBar(tester);
      final callsBefore = visibilityCalls.length;
      await tester.pump(const Duration(seconds: 3));
      expect(visibilityCalls.length, callsBefore + 1);
      expect(statusBarHidden(), isTrue);

      revealStatusBar(tester);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(statusBarHidden(), isFalse);
    });
  });

  group('StatusBarStableInset', () {
    const channel = MethodChannel('night_reader/system_bars');

    /// 以邏輯像素設定系統回報的上緣內距（測試裝置像素比為 2）。
    void setSystemTop(WidgetTester tester, double top) {
      tester.view.padding = FakeViewPadding(top: top * 2);
      tester.view.viewPadding = FakeViewPadding(top: top * 2);
    }

    Future<double Function()> pumpInset(
      WidgetTester tester,
      Future<double> Function() statusBarExtent,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(800, 1600);
      setSystemTop(tester, 32);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) => statusBarExtent());
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      late double top;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => StatusBarStableInset(child: child!),
          home: Builder(
            builder: (context) {
              top = MediaQuery.paddingOf(context).top;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();
      return () => top;
    }

    testWidgets('狀態列收起時頁面仍保留狀態列原本的高度', (tester) async {
      final top = await pumpInset(tester, () async => 32);
      expect(top(), 32);

      // 閱讀頁收起狀態列後，系統只回報挖孔高度。
      setSystemTop(tester, 20);
      await tester.pump();
      expect(top(), 32);

      setSystemTop(tester, 32);
      await tester.pump();
      expect(top(), 32);
    });

    testWidgets('視窗尺寸改變後，重新量到前不沿用舊尺寸的高度', (tester) async {
      var extent = 32.0;
      Completer<double>? held;
      final top = await pumpInset(
        tester,
        () => held?.future ?? Future<double>.value(extent),
      );
      expect(top(), 32);

      // 轉成橫向：狀態列變矮，原生端尚未回報新高度。
      held = Completer<double>();
      tester.view.physicalSize = const Size(1600, 800);
      setSystemTop(tester, 24);
      await tester.pump();
      expect(top(), 24);

      extent = 24;
      held.complete(extent);
      held = null;
      await tester.pump();
      setSystemTop(tester, 0);
      await tester.pump();
      expect(top(), 24);
    });
  });
}
