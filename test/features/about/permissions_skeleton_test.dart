// 權限尚未回報時保留完整七列骨架，回報後照真實狀態逐塊對齊。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/app_permission_service.dart';
import 'package:night_reader/features/about/privacy_pages.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import '../../support/skeleton_match.dart';

class _DelayedGateway implements AppPermissionGateway {
  final Completer<AppPermissionState> notification = Completer();

  @override
  Future<AppPermissionState> status(AppPermissionTarget target) =>
      notification.future;

  @override
  Future<AppPermissionState> request(AppPermissionTarget target) async =>
      AppPermissionState.granted;

  @override
  Future<bool> openSystemSettings() async => true;
}

void main() {
  testWidgets('權限先有五列狀態與兩列操作，真正狀態到齊才揭開', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final gateway = _DelayedGateway();
    final service = AppPermissionService(
      gateway: gateway,
      isAndroid: () => true,
      isIOS: () => false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PermissionsPage(service: service),
                  ),
                ),
                child: const Text('開啟'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開啟'));
    await tester.pump();
    final list = find.byType(GroupedListView);
    final route = ModalRoute.of(tester.element(list))!;
    while (!route.animation!.isCompleted) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // 系統權限查詢比換頁慢時，骨架不能先變成轉圈或空卡片。
    await tester.pump(const Duration(seconds: 1));
    final waiting = skeletonLayoutOf(
      tester,
      find.descendant(of: list, matching: find.byType(SkeletonShapes)),
    );
    expect(waiting.marks.length, greaterThan(10));
    expect(find.text('開啟系統設定'), findsNothing);

    gateway.notification.complete(AppPermissionState.granted);
    await tester.pump();
    await tester.pump();
    final ready = skeletonLayoutOf(
      tester,
      find.descendant(of: list, matching: find.byType(SkeletonShapes)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonShapes), findsNothing);
    expect(find.text('已允許'), findsOneWidget);
    expect(find.text('開啟系統設定'), findsOneWidget);
    expect(
      skeletonMismatches(
        ready,
        contentLayoutOf(tester, list),
        visible: tester.getRect(list),
      ),
      isEmpty,
    );
  });
}
