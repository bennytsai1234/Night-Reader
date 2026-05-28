import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/features/source_manager/source_manager_page.dart';

class _FakeSourceDao extends Fake implements BookSourceDao {
  @override
  Future<List<BookSource>> getAllPart() async => <BookSource>[];

  @override
  Future<List<BookSource>> getAll() async => <BookSource>[];

  @override
  Future<BookSource?> getByUrl(String url) async => null;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GetIt.instance.registerLazySingleton<BookSourceDao>(() => _FakeSourceDao());
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets('SourceManagerPage can render with the new check result flow', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SourceManagerPage()));
    await tester.pumpAndSettle();

    expect(find.text('書源管理'), findsOneWidget);
    expect(find.text('暫無書源'), findsOneWidget);
  });
}
