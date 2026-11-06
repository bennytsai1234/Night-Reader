import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/update_preferences.dart';
import 'package:night_reader/core/services/update_service.dart';
import 'package:night_reader/features/about/release_notes_page.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeService extends AppUpdateService {
  _FakeService(this.results)
    : super(dio: Dio(), currentVersionLoader: () async => '0.3.3');

  /// 每次載入依序取一個結果；[Exception] 代表這次載入失敗。
  final List<Object> results;
  final includeBetaCalls = <bool>[];

  @override
  Future<List<ReleaseNote>> fetchReleaseNotes({
    bool includeBeta = false,
  }) async {
    includeBetaCalls.add(includeBeta);
    final result = results.removeAt(0);
    if (result is Exception) throw result;
    if (result is Future<List<ReleaseNote>>) return result;
    return result as List<ReleaseNote>;
  }
}

/// 一直等到 [notes] 完成才回應。
class _PendingService extends AppUpdateService {
  _PendingService(this.notes)
    : super(dio: Dio(), currentVersionLoader: () async => '0.3.3');

  final Future<List<ReleaseNote>> notes;

  @override
  Future<List<ReleaseNote>> fetchReleaseNotes({bool includeBeta = false}) =>
      notes;
}

final _notes = [
  ReleaseNote(
    versionName: '0.3.4-beta.1',
    publishedAt: DateTime(2026, 10, 1),
    body: '- 閱讀時記住位置',
    isCurrent: false,
  ),
  const ReleaseNote(
    versionName: '0.3.3',
    publishedAt: null,
    body: '',
    isCurrent: true,
  ),
];

Future<void> _pumpPage(WidgetTester tester, AppUpdateService service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ReleaseNotesPage(
        service: service,
        preferences: UpdatePreferences(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('lists each version with its notes and marks the current one', (
    tester,
  ) async {
    await _pumpPage(tester, _FakeService([_notes]));

    expect(find.text('v0.3.4-beta.1'), findsOneWidget);
    expect(find.text('2026-10-01'), findsOneWidget);
    expect(find.text('• 閱讀時記住位置'), findsOneWidget);
    expect(find.text('v0.3.3（目前版本）'), findsOneWidget);
    expect(find.text('這個版本沒有附更新說明。'), findsOneWidget);
  });

  testWidgets('follows the beta channel setting', (tester) async {
    SharedPreferences.setMockInitialValues({'update.beta_channel': true});
    final service = _FakeService([_notes]);

    await _pumpPage(tester, service);

    expect(service.includeBetaCalls, [true]);
  });

  testWidgets('a failed load can be retried', (tester) async {
    await _pumpPage(tester, _FakeService([Exception('offline'), _notes]));

    expect(find.text('更新紀錄載入失敗'), findsOneWidget);
    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();

    expect(find.text('v0.3.3（目前版本）'), findsOneWidget);
  });

  testWidgets('loading shows the list skeleton, not a spinner', (tester) async {
    final pending = Completer<List<ReleaseNote>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReleaseNotesPage(
          service: _PendingService(pending.future),
          preferences: UpdatePreferences(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(GroupedListView), findsOneWidget);
    expect(find.bySemanticsLabel('正在載入更新紀錄'), findsOneWidget);

    pending.complete(_notes);
    await tester.pumpAndSettle();
    expect(find.text('v0.3.3（目前版本）'), findsOneWidget);
  });

  testWidgets('a retry keeps the error view and says it is loading', (
    tester,
  ) async {
    final pending = Completer<List<ReleaseNote>>();
    await _pumpPage(
      tester,
      _FakeService([Exception('offline'), pending.future]),
    );

    await tester.tap(find.text('重試'));
    await tester.pump();
    expect(find.text('更新紀錄載入失敗'), findsOneWidget);
    expect(find.text('重新載入中…'), findsOneWidget);
    expect(find.text('重試'), findsNothing);

    pending.complete(_notes);
    await tester.pumpAndSettle();
    expect(find.text('v0.3.3（目前版本）'), findsOneWidget);
  });

  testWidgets('an empty list says so', (tester) async {
    await _pumpPage(tester, _FakeService([<ReleaseNote>[]]));

    expect(find.text('目前沒有更新紀錄'), findsOneWidget);
  });
}
