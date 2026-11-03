import 'dart:async';
import 'dart:isolate';

import 'sync_records.dart';

/// 把一段純計算交給別的執行緒跑，傳回它的結果。預設是 [Isolate.run]；
/// 元件測試的假時間裡等不到別的 isolate 回覆，改給 [runSyncWorkInline]。
typedef SyncRunner = Future<R> Function<R>(FutureOr<R> Function() work);

/// 同步裡的解 JSON、算指紋與合併在背景 isolate 跑，不佔畫面的主執行緒
/// （ADR 0046）。交進來的 [work] 只能捕捉資料與頂層、靜態函式，捕捉到資料庫
/// 或服務物件會送不過去。
Future<R> runSyncWorkInBackground<R>(FutureOr<R> Function() work) =>
    Isolate.run(work, debugName: 'sync');

/// 在目前的執行緒直接跑，給元件測試用。
Future<R> runSyncWorkInline<R>(FutureOr<R> Function() work) async => work();

/// 讀雲端的檔案，並拿掉雲端已經不算數的（[prune]）。
Map<String, SyncRecord> decodeSyncFile(String content, SyncPrune prune) =>
    prune(SyncDocument.decode(content).records);

// 下面三個把工作交給 [SyncRunner]。閉包在頂層函式裡建立，只捕捉參數裡的
// 資料：在 `SyncService` 的方法裡建立的話，會連同同一層別的閉包捕捉的
// `this`、同步空間一起送出去（CODING_STANDARDS.md）。

Future<Map<String, SyncRecord>> decodeSyncFileOn(
  SyncRunner run,
  String content,
  SyncPrune prune,
) => run(() => decodeSyncFile(content, prune));

Future<SyncMergePlan> planSyncMergeOn(SyncRunner run, SyncMergeInput input) =>
    run(() => planSyncMerge(input));

/// 一種資料這一輪要合併的東西。都是資料與頂層、靜態函式，整份送得進背景
/// isolate。
class SyncMergeInput {
  const SyncMergeInput({
    required this.remote,
    required this.local,
    required this.base,
    required this.now,
    required this.fingerprint,
    required this.hasOwnTime,
    required this.syncsDeletion,
  });

  /// 雲端的每一筆（已拿掉不算數的）。
  final Map<String, SyncRecord> remote;

  /// 這台的每一筆（已和雲端對齊身分），時間還沒補。
  final Map<String, SyncRecord> local;

  /// 上次同步的紀錄。
  final Map<String, SyncBaseEntry> base;

  /// 這次同步的時間（毫秒）。
  final int now;
  final SyncFingerprint fingerprint;
  final bool hasOwnTime;
  final bool syncsDeletion;
}

/// 合併的結果：雲端要不要改、上次同步的紀錄改成什麼、哪些要套用到這台。
class SyncMergePlan {
  const SyncMergePlan({
    required this.upload,
    required this.base,
    required this.incoming,
  });

  /// 雲端要改成的整份檔案（已編碼）；雲端不用改時是 null。
  final String? upload;

  /// 下一份上次同步的紀錄，還不含這次套用到這台的那些筆。
  final Map<String, SyncBaseEntry> base;

  /// 雲端較新、要套用到這台的那些筆：鍵 → 合併時這台那筆的樣子（補過時間，
  /// 沒有就是 null）與指紋。套用前和重讀的這台比，變了就不套用。
  final Map<String, ({SyncRecord? mine, String? print})> incoming;
}

/// 每筆和上次同步時三方比對（[decideSync]），算出 [SyncMergePlan]。純計算，
/// 在背景 isolate 跑。
SyncMergePlan planSyncMerge(SyncMergeInput input) {
  final SyncMergeInput(:remote, :base, :fingerprint) = input;
  final local = timedSyncRecords(input);
  final nextRemote = Map.of(remote);
  final nextBase = <String, SyncBaseEntry>{};
  final incoming = <String, ({SyncRecord? mine, String? print})>{};
  for (final key in {...local.keys, ...remote.keys}) {
    final mine = local[key];
    final theirs = remote[key];
    switch (decideSync(
      local: mine,
      remote: theirs,
      base: base[key],
      fingerprint: fingerprint,
    )) {
      case SyncDecision.same:
        if (mine != null && theirs != null) {
          nextBase[key] = SyncBaseEntry(
            local: fingerprint(mine),
            remote: fingerprint(theirs),
            time: theirs.time,
          );
        } else if (base[key] case final kept?) {
          nextBase[key] = kept;
        }
      case SyncDecision.upload:
        nextRemote[key] = mine!;
        nextBase[key] = SyncBaseEntry(
          local: fingerprint(mine),
          remote: fingerprint(mine),
          time: mine.time,
        );
      case SyncDecision.apply:
        incoming[key] = (
          mine: mine,
          print: mine == null ? null : fingerprint(mine),
        );
        if (base[key] case final kept?) nextBase[key] = kept;
    }
  }
  return SyncMergePlan(
    upload: _sameRecords(remote, nextRemote)
        ? null
        : SyncDocument(nextRemote).encode(),
    base: nextBase,
    incoming: incoming,
  );
}

/// 補上這台每筆的修改時間與刪除紀錄。有自己記時間的（`hasOwnTime`）照原樣。
/// 其他的照上次同步的紀錄推算：
///
/// - 和上次同步時一樣：沿用上次的時間。
/// - 改過了（或上次之後才新增的）：算成這次同步的時間。
/// - 從沒同步過、雲端也有同一筆：時間算 0，內容不同時雲端的贏。剛開始用
///   同步、或重裝後第一次同步的這台，不拿手上可能是舊的資料蓋掉雲端。
/// - 上次同步時有、現在沒有：這台刪掉了，補一筆刪除紀錄讓別台跟著刪
///   （`syncsDeletion`）。
Map<String, SyncRecord> timedSyncRecords(SyncMergeInput input) {
  if (input.hasOwnTime) return input.local;
  return {
    for (final key in {
      ...input.local.keys,
      if (input.syncsDeletion) ...input.base.keys,
    })
      key: ?timedSyncRecordOf(input, key),
  };
}

/// [timedSyncRecords] 的其中一筆；這台沒有、也不算刪掉的是 null。套用前
/// 重讀這台時只算要套用的那幾筆，在主執行緒讀完就比，中間不等別的執行緒，
/// 讀到比的這段時間不會讓使用者剛改的被蓋掉。
SyncRecord? timedSyncRecordOf(SyncMergeInput input, String key) {
  final SyncMergeInput(:remote, :base, :now, :fingerprint) = input;
  final record = input.local[key];
  if (input.hasOwnTime) return record;
  final last = base[key];
  if (record != null) {
    final time = switch (last) {
      null => remote.containsKey(key) ? 0 : now,
      _ when fingerprint(record) == last.local => last.time,
      _ => now,
    };
    return SyncRecord(time: time, data: record.data, deleted: record.deleted);
  }
  if (!input.syncsDeletion || last == null) return null;
  final gone = SyncRecord(time: now, data: const {}, deleted: true);
  return fingerprint(gone) == last.local
      ? SyncRecord(time: last.time, data: const {}, deleted: true)
      : gone;
}

bool _sameRecords(Map<String, SyncRecord> a, Map<String, SyncRecord> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!identical(b[entry.key], entry.value)) return false;
  }
  return true;
}
