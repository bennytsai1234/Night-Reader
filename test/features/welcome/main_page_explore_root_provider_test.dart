import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';

import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/explore/explore_provider.dart';

class _RecordingSourceDao extends Fake implements BookSourceDao {
  int watchCallCount = 0;
  final _ctrl = StreamController<List<BookSource>>.broadcast();

  @override
  Stream<List<BookSource>> watchDiscoveryPart() {
    watchCallCount++;
    return _ctrl.stream;
  }

  @override
  Future<List<BookSource>> getDiscoveryPart() async => const <BookSource>[];

  Future<void> close() => _ctrl.close();
}

void main() {
  late _RecordingSourceDao dao;

  setUp(() {
    dao = _RecordingSourceDao();
    GetIt.instance.registerLazySingleton<BookSourceDao>(() => dao);
  });

  tearDown(() async {
    await dao.close();
    await GetIt.instance.reset();
  });

  testWidgets(
    'ExploreProvider with lazy:false subscribes to DAO immediately on app start',
    (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ExploreProvider(),
              lazy: false,
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
        ),
      );
      expect(dao.watchCallCount, 1);
    },
  );
}
