import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';

/// 匯入預覽照更新時間分新舊（同 Legado 的 ImportBookSourceViewModel）：檔案
/// 比這台新的預先勾覆蓋；一樣的無變化；比這台舊的另列、預設不勾，這台改過或
/// 修好的才不會被舊檔蓋回去。
void main() {
  late AppDatabase db;
  late SourceImportService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final dao = BookSourceDao(db);
    service = SourceImportService(dao: dao);
    await dao.upsert(
      BookSource(
        bookSourceUrl: 'https://a.example',
        bookSourceName: '甲',
        lastUpdateTime: 2000,
      ),
    );
  });

  tearDown(() => db.close());

  BookSource incoming(String url, int time) =>
      BookSource(bookSourceUrl: url, bookSourceName: '甲', lastUpdateTime: time);

  test('a newer one in the file overwrites', () async {
    final preview = await service.previewImport([
      incoming('https://a.example', 3000),
    ]);
    expect(preview.updatedSources, hasLength(1));
    expect(preview.olderSources, isEmpty);
    expect(preview.unchangedSources, isEmpty);
  });

  test('the same one is unchanged', () async {
    final preview = await service.previewImport([
      incoming('https://a.example', 2000),
    ]);
    expect(preview.unchangedSources, hasLength(1));
    expect(preview.updatedSources, isEmpty);
    expect(preview.olderSources, isEmpty);
  });

  test('an older one in the file is listed apart', () async {
    final preview = await service.previewImport([
      incoming('https://a.example', 1000),
      incoming('https://b.example', 1000),
    ]);
    expect(preview.olderSources.map((s) => s.bookSourceUrl), [
      'https://a.example',
    ]);
    expect(preview.updatedSources, isEmpty);
    expect(preview.newSources.map((s) => s.bookSourceUrl), [
      'https://b.example',
    ]);
  });

  test('a file with the same source twice keeps its latest', () async {
    final preview = await service.previewImport([
      incoming('https://a.example', 3000),
      incoming('https://a.example', 1000),
    ]);
    expect(preview.updatedSources.map((s) => s.lastUpdateTime), [3000]);
    expect(preview.olderSources, isEmpty);
    expect(preview.total, 1);
  });
}
