import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';

void main() {
  late Directory directory;
  late SyncBaseStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sync-base-storage');
    storage = SyncBaseStorage(directory: () async => directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('simultaneous JSON writes leave one complete document', () async {
    final first = {'writer': '第一份', 'items': List.filled(100, '甲')};
    final second = {'writer': '第二份', 'items': List.filled(100, '乙')};

    await Future.wait([
      storage.writeJson('base_books', first),
      storage.writeJson('base_books', second),
    ]);

    final saved = jsonDecode(
      await File('${directory.path}/base_books.json').readAsString(),
    );
    expect(saved, anyOf(equals(first), equals(second)));
  });
}
