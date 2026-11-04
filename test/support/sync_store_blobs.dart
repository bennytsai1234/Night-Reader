import 'dart:typed_data';

/// 測試用假同步空間的二進位檔（同步本地書的原檔），記在記憶體裡。假空間
/// `with SyncStoreBlobs implements SyncStore` 就有 `readBytes`、`writeBytes`、
/// `delete`。
mixin SyncStoreBlobs {
  final Map<String, Uint8List> blobs = {};

  /// 檔名 → 讀寫這個檔時丟的錯（模擬某個檔傳不了、整個空間連不上）。
  final Map<String, Object> failingBlobs = {};

  Future<Uint8List?> readBytes(String name) async {
    if (failingBlobs[name] case final error?) throw error;
    return blobs[name];
  }

  Future<void> writeBytes(String name, Uint8List bytes) async {
    if (failingBlobs[name] case final error?) throw error;
    blobs[name] = Uint8List.fromList(bytes);
  }

  Future<void> delete(String name) async {
    if (failingBlobs[name] case final error?) throw error;
    blobs.remove(name);
  }
}
