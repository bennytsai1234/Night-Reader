import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/source_debug_service.dart';
import 'package:night_reader/features/source_manager/source_debug_page.dart';

class _FakeDebugService implements SourceDebugService {
  final StreamController<DebugLog> controller =
      StreamController<DebugLog>.broadcast();
  final Completer<void> runCompleter = Completer<void>();

  @override
  Stream<DebugLog> get logStream => controller.stream;

  @override
  void cancel() {}

  @override
  void log(String msg, {int state = 1, bool isHtml = false}) {
    controller.add(DebugLog(state, msg, DateTime(2026)));
  }

  @override
  Future<void> startDebug(BookSource source, String key) => runCompleter.future;
}

void main() {
  testWidgets('clipboard failure is reported without a false success message', (
    tester,
  ) async {
    final service = _FakeDebugService();
    await tester.pumpWidget(
      MaterialApp(
        home: SourceDebugPage(
          source: BookSource(
            bookSourceUrl: 'https://source.test',
            bookSourceName: '書源',
          ),
          debugKey: '關鍵字',
          debugService: service,
          writeClipboard: (ClipboardData data) async {
            throw StateError('clipboard unavailable');
          },
        ),
      ),
    );
    await tester.pump();
    service.log('可複製日誌');
    await tester.pump();

    await tester.tap(find.byTooltip('複製完整日誌'));
    await tester.pump();

    expect(find.textContaining('複製日誌失敗'), findsOneWidget);
    expect(find.text('已複製完整日誌至剪貼簿'), findsNothing);
    expect(tester.takeException(), isNull);

    service.runCompleter.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await service.controller.close();
  });
}
