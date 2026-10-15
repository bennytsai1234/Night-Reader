import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';

void main() {
  test('watchHasAny follows sources being imported and removed', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = BookSourceDao(db);
    final values = <bool>[];
    final sub = dao.watchHasAny().listen(values.add);
    addTearDown(sub.cancel);

    await pumpEventQueue();
    await dao.upsert(
      BookSource(bookSourceUrl: 'https://s.example', bookSourceName: '書源'),
    );
    await pumpEventQueue();
    await db.delete(db.bookSources).go();
    await pumpEventQueue();

    expect(values, [false, true, false]);
  });
}
