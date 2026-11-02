import 'sync_records.dart';

/// 一種要同步的資料（書源、替換規則、書架、閱讀進度……），同步空間裡一份
/// 檔案。合併的流程由 `SyncService` 統一做，這裡只回答：本機有哪些、內容
/// 怎麼比、雲端的怎麼套用到這台（ADR 0039）。
abstract class SyncKind {
  /// 上次同步紀錄的名稱，也是同步空間裡的檔名（`<name>.json`）。
  String get name;

  String get fileName => '$name.json';

  /// 每筆有自己記的修改時間（進度的位置移動時間）。沒有的，由同步服務照
  /// 上次同步的紀錄推算：沒改過沿用上次的時間，改過了算成這次同步的時間。
  bool get hasOwnTime => false;

  /// 這台刪掉的，別台也跟著刪。不跟著刪的（登入資料、進度），這台刪掉只
  /// 是這台沒有了，雲端那筆留著，之後別台改了才再套用過來。
  bool get syncsDeletion => true;

  /// 本機現在的每一筆，鍵是兩台共通的身分（書源網址、書名加作者……）。
  /// [hasOwnTime] 為 false 時時間填什麼都可以。
  Future<Map<String, SyncRecord>> local();

  /// 兩筆算不算內容一樣；上次同步的紀錄也用它算。
  String fingerprint(SyncRecord record) => record.fingerprint;

  /// 雲端的這筆能不能現在套用到這台；不能的留在雲端，下次再比。
  bool canApply(String key, SyncRecord? local) => true;

  /// 讀到雲端之後、比對之前，把雲端已經不算數的拿掉（例如過期的登入資料）。
  Map<String, SyncRecord> prune(Map<String, SyncRecord> remote) => remote;

  /// 比對之前把本機和雲端的身分對齊（替換規則的編號）。傳回對齊後的本機。
  Future<Map<String, SyncRecord>> reconcile(
    Map<String, SyncRecord> local,
    Map<String, SyncRecord> remote,
    Map<String, SyncBaseEntry> base,
  ) async => local;

  /// 把雲端的這些筆（含刪除）套用到這台，傳回套用後本機的每一筆；刪掉的
  /// 或這台不存的是刪除紀錄。
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote);
}
