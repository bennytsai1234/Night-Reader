import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_settings.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:night_reader/features/settings/webdav_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store implements SyncStore {
  _Store({this.fail});

  final String? fail;

  @override
  Future<void> check() async {
    if (fail != null) throw SyncStoreException(fail!);
  }

  @override
  Future<SyncFile?> read(String name) async => null;

  @override
  Future<String?> version(String name) async => null;

  @override
  Future<void> write(
    String name,
    String content, {
    String? ifVersion,
    bool ifAbsent = false,
  }) async {}
}

void main() {
  late Directory bases;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bases = Directory.systemTemp.createTempSync('nr-webdav-page');
    addTearDown(() => bases.delete(recursive: true));
  });

  Future<SyncService> pump(WidgetTester tester, _Store store) async {
    final sync = SyncService(
      storeFactory: (space, _) => space == SyncSpace.none ? null : store,
      bases: SyncBaseStorage(directory: () async => bases),
    );
    await tester.pumpWidget(MaterialApp(home: WebDavSettingsPage(sync: sync)));
    await tester.pumpAndSettle();
    return sync;
  }

  testWidgets('a wrong password is shown and nothing is saved', (tester) async {
    await pump(tester, _Store(fail: '帳號或密碼不對'));
    await tester.enterText(find.byType(TextField).at(0), 'https://dav.example');
    await tester.tap(find.text('連線並開始同步'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('帳號或密碼不對'), findsOneWidget);
    expect(await SyncSettings().space(), SyncSpace.none);
  });

  testWidgets('an empty address asks for one first', (tester) async {
    await pump(tester, _Store());
    await tester.tap(find.text('連線並開始同步'));
    await tester.pumpAndSettle();
    expect(find.text('先填 WebDAV 的網址'), findsOneWidget);
  });
}
