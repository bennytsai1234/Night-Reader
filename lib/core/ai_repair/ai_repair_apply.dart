import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_source_service.dart';

import 'ai_repair_backups.dart';
import 'ai_repair_prompt.dart';

/// 存修好的書源（AI 修好、換網址或套用同網站修好的規則，ADR 0054）。修的
/// 這段時間書源被刪掉或改過（例如同步）時不存：存了會蓋掉別處的改動、或把
/// 刪掉的書源加回來。網址換了開頭時照書源編輯改網址的做法搬過去，書架上的
/// 書跟著搬；新網址已經有別的書源時不存。存之前留下改前的版本。
Future<void> saveRepairedSource(
  BookSource repaired,
  BookSource original, {
  AiRepairBackups? backups,
}) async {
  final dao = getIt<BookSourceDao>();
  final current = await dao.getByUrl(original.bookSourceUrl);
  if (current == null) {
    throw const AiRepairConflict('修的這段時間書源被刪掉了，沒有存。');
  }
  if (changedParts(original, current).isNotEmpty ||
      current.bookSourceName != original.bookSourceName) {
    throw const AiRepairConflict('修的這段時間書源被改過了（例如同步），沒有存。');
  }
  // 修好了：之前標的「AI 修不好」拿掉。開關、排序與權重照現在的：修的這段
  // 時間在別處（例如同步）改了，不蓋回修之前的值。
  repaired
    ..removeGroup(aiUnfixableSourceGroupTag)
    ..enabled = current.enabled
    ..enabledExplore = current.enabledExplore
    ..customOrder = current.customOrder
    ..weight = current.weight;
  final moved = repaired.bookSourceUrl != original.bookSourceUrl;
  if (moved && await dao.getByUrl(repaired.bookSourceUrl) != null) {
    throw AiRepairConflict('新網址 ${repaired.bookSourceUrl} 已經有別的書源，沒有存。');
  }
  await (backups ?? AiRepairBackups.instance).put(
    repaired.bookSourceUrl,
    current.toJson(),
  );
  await BookSourceService().saveEditedSource(
    repaired,
    previousUrl: moved ? original.bookSourceUrl : null,
  );
}

/// 修好的書源存不進去：修的這段時間書源被刪掉或改過。
class AiRepairConflict implements Exception {
  const AiRepairConflict(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 把書源還原成 AI 改之前的那份，並刪掉留著的改前版本。AI 換過網址開頭
/// 的，網址也換回去，書架上的書跟著搬回去。
///
/// 傳回真的還原了沒：沒有改前版本、或書源已經刪掉了是 false。
Future<bool> restoreAiRepair(
  String sourceUrl, {
  AiRepairBackups? backups,
}) async {
  final store = backups ?? AiRepairBackups.instance;
  final json = await store.get(sourceUrl);
  if (json == null) return false;
  // 書源已經刪掉了（例如另一台同步刪的）：不還原，免得把它加回來。
  final current = await getIt<BookSourceDao>().getByUrl(sourceUrl);
  if (current == null) {
    await store.remove(sourceUrl);
    return false;
  }
  // 換回改前的規則也是改了一版：記下時間，匯入預覽才認得這是新的一版；
  // 規則和現在一樣就照現在的。
  final previous = BookSource.fromJson(json);
  previous.lastUpdateTime = rulesChanged(current, previous)
      ? DateTime.now().millisecondsSinceEpoch
      : current.lastUpdateTime;
  await BookSourceService().saveEditedSource(
    previous,
    previousUrl: previous.bookSourceUrl == sourceUrl ? null : sourceUrl,
  );
  await store.remove(sourceUrl);
  return true;
}
