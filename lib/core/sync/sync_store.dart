import 'dart:typed_data';

/// 同步空間裡讀到的一份檔案，與它目前的版本（WebDAV 的 ETag）。
class SyncFile {
  const SyncFile(this.content, {this.version});

  final String content;

  /// 寫回時帶上，檔案在這之間被別台改過就不寫（[SyncConflict]）；同步空間
  /// 不提供版本時是 null，直接寫。
  final String? version;
}

/// 同步空間：放同步資料的地方（Google 雲端硬碟或 WebDAV，ADR 0039）。只負責
/// 讀寫檔案，怎麼合併和放在哪裡無關。
abstract interface class SyncStore {
  /// 試連一次，連得上、帳號密碼對、資料夾建得起來才正常結束。
  Future<void> check();

  /// 讀一份檔案；還沒有這份時傳回 null。
  Future<SyncFile?> read(String name);

  /// 一份檔案目前的版本（和 [read] 給的 [SyncFile.version] 同一種），不下載
  /// 內容；還沒有這份、或同步空間不提供版本時傳回 null。用來在兩邊都沒變
  /// 時跳過一整種資料。
  Future<String?> version(String name);

  /// 寫一份檔案。[ifVersion] 給了的話，檔案已經不是那個版本就丟
  /// [SyncConflict]；[ifAbsent] 為 true 時檔案已經存在就丟 [SyncConflict]。
  Future<void> write(
    String name,
    String content, {
    String? ifVersion,
    bool ifAbsent = false,
  });

  /// 讀一個二進位檔（同步本地書的原檔）；還沒有這個檔時傳回 null。
  Future<Uint8List?> readBytes(String name);

  /// 寫一個二進位檔，已經有就整個換掉。原檔用指紋命名、內容不會變，不比
  /// 版本。
  Future<void> writeBytes(String name, Uint8List bytes);

  /// 刪掉一個檔；本來就沒有也正常結束。
  Future<void> delete(String name);
}

/// 寫入時檔案已經被別台改過；重讀、再合併一次。
class SyncConflict implements Exception {
  const SyncConflict();
}

/// 同步失敗，[message] 是給使用者看的原因。
class SyncStoreException implements Exception {
  /// 整個同步空間用不了（連不上、授權失效、網址不對）：後面的檔案也一樣會
  /// 失敗，這一輪不必再試。
  const SyncStoreException(this.message) : wholeSpace = true;

  /// 只有這一份檔案失敗（例如雲端對它回 403）：其他檔案照常同步，這一輪
  /// 最後仍算失敗。
  const SyncStoreException.file(this.message) : wholeSpace = false;

  final String message;

  /// 見 [SyncStoreException.new]、[SyncStoreException.file]。
  final bool wholeSpace;

  @override
  String toString() => message;
}
