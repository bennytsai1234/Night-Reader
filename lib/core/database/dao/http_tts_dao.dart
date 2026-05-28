import 'package:drift/drift.dart';
import '../../models/http_tts.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'http_tts_dao.g.dart';

@DriftAccessor(tables: [HttpTtsTable])
class HttpTtsDao extends DatabaseAccessor<AppDatabase> with _$HttpTtsDaoMixin {
  HttpTtsDao(super.db);

  Future<List<HttpTTS>> getAll() => select(httpTtsTable).get();

  Future<HttpTTS?> getById(int id) =>
      (select(httpTtsTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<List<HttpTTS>> watchAll() => select(httpTtsTable).watch();

  Future<void> upsert(HttpTTS tts) => into(
    httpTtsTable,
  ).insertOnConflictUpdate(HttpTTSToInsertable(tts).toInsertable());

  Future<int> create(HttpTTS tts) {
    return into(httpTtsTable).insert(
      HttpTtsTableCompanion.insert(
        name: tts.name,
        url: tts.url,
        contentType: Value.absentIfNull(tts.contentType),
        concurrentRate: Value.absentIfNull(tts.concurrentRate),
        loginUrl: Value.absentIfNull(tts.loginUrl),
        loginUi: Value.absentIfNull(tts.loginUi),
        header: Value.absentIfNull(tts.header),
        jsLib: Value.absentIfNull(tts.jsLib),
        enabledCookieJar: Value(tts.enabledCookieJar),
        loginCheckJs: Value.absentIfNull(tts.loginCheckJs),
        lastUpdateTime: Value(tts.lastUpdateTime),
      ),
    );
  }

  Future<void> deleteById(int id) =>
      (delete(httpTtsTable)..where((t) => t.id.equals(id))).go();

  Future<void> insertOrUpdateAll(List<HttpTTS> engines) async {
    await batch(
      (b) => b.insertAllOnConflictUpdate(
        httpTtsTable,
        engines.map((e) => HttpTTSToInsertable(e).toInsertable()).toList(),
      ),
    );
  }
}
