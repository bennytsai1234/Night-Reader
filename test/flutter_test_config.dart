import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 每個測試檔開始前都會跑（`flutter test` 自動載入）。
///
/// 測試裡沒有真的平台，問「App 資料夾在哪」的平台呼叫在元件測試
/// （`testWidgets`）裡永遠等不到回覆：測試卡住，`--timeout` 也停不了它。
/// 所以每個測試檔一律先換成這裡的假資料夾，放在這個檔自己的暫存目錄，
/// 跑完刪掉。要別的位置的測試照舊自己換 [PathProviderPlatform.instance]。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final root = await Directory.systemTemp.createTemp('night_reader_test_');
  PathProviderPlatform.instance = TestPathProvider(root.path);
  tearDownAll(() async {
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // Windows 上檔案還被開著時刪不掉，留給系統清暫存。
    }
  });
  await testMain();
}

/// 文件、支援、暫存、下載、外部儲存都放在 [root] 底下各自的子資料夾。
/// 每次問都建一次，測試刪掉資料夾後再問也拿得到。
class TestPathProvider extends PathProviderPlatform {
  TestPathProvider(this.root);

  final String root;

  /// 和真的平台一樣，給出去的資料夾已經存在。
  String _dir(String name) {
    final path = p.join(root, name);
    Directory(path).createSync(recursive: true);
    return path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir('documents');

  @override
  Future<String?> getApplicationSupportPath() async => _dir('support');

  @override
  Future<String?> getApplicationCachePath() async => _dir('cache');

  @override
  Future<String?> getTemporaryPath() async => _dir('temporary');

  @override
  Future<String?> getLibraryPath() async => _dir('library');

  @override
  Future<String?> getDownloadsPath() async => _dir('downloads');

  @override
  Future<String?> getExternalStoragePath() async => _dir('external');

  @override
  Future<List<String>?> getExternalCachePaths() async => [
    _dir('external_cache'),
  ];

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async => [_dir('external')];
}
