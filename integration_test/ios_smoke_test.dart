// iPhone 版的最小自動檢查（ADR 0003）：發版流程在 iPhone 模擬器上打開夜讀，
// 走一遍進書架、匯入一本 TXT、開書、進「閱讀偏好」，打不開、閃退、畫面出現
// 「這部分無法顯示」或留下崩潰日誌就失敗，那一版不附 IPA。
//
// 模擬器上沒有人點系統的選檔畫面：選檔換成直接交出這裡寫好的 TXT，其餘照
// 讀者的操作。夜讀自己攔下錯誤、不會閃退，所以每一步都等到該出現的畫面才算過。
//
//   flutter test integration_test/ios_smoke_test.dart -d <模擬器>
import 'dart:io';

// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:night_reader/core/diagnostics/crash_handler.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/features/reader/text_view/overlay/loading_veil.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'package:night_reader/main.dart' as app;
import 'package:path/path.dart' as p;

/// 書名用簡繁同形的字：介面跟著系統語言轉簡體時也找得到。
const _bookName = '山中月';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('打開夜讀、匯入 TXT、開書、進設定', (tester) async {
    final temp = await AppStoragePaths.temporaryDir();
    final txt = File(p.join(temp.path, '$_bookName.txt'));
    await txt.writeAsString(_chapters());
    FilePickerPlatform.instance = _PickOneFile(txt.path);

    // 點不到（被進場、換頁動畫蓋住）就失敗，不要默默點空。
    WidgetController.hitTestWarningShouldBeFatal = true;

    // 夜讀換掉這兩個錯誤處理。失敗的例外丟回測試框架之前就要換回來，框架
    // 才記得下這次失敗、結束測試（換不回來時它停在斷言、一直不結束）。
    final onError = FlutterError.onError;
    final errorWidget = ErrorWidget.builder;
    try {
      app.main();
      await _walkThrough(tester);
    } finally {
      FlutterError.onError = onError;
      ErrorWidget.builder = errorWidget;
    }

    final logs = await CrashHandler.readLogs();
    expect(logs, isEmpty, reason: '走完一遍留下了崩潰日誌：\n${logs.join('\n')}');
  });
}

Future<void> _walkThrough(WidgetTester tester) async {
  // 1. 進書架：新裝的夜讀沒有書源，空書架上有「加入本地書籍」。進場播完才點得到。
  await _tapWhenReady(tester, '書架上的「加入本地書籍」', find.text('加入本地書籍'));

  // 2. 匯入 TXT：書名出現在書架上。
  await _tapWhenReady(tester, '匯入後的書卡', find.text(_bookName));

  // 3. 開書：閱讀器載入的紙掀開，表示第一頁的正文排好了。
  await _waitFor(
    tester,
    '閱讀器',
    () => find.byType(LoadingVeil).evaluate().isNotEmpty,
  );
  await _waitFor(tester, '閱讀器的正文排好', _veilLifted, stable: 5);

  // 4. 返回書架，到「我的」進「閱讀偏好」。
  await tester.binding.handlePopRoute();
  await _tapWhenReady(tester, '分頁列的「我的」', find.text('我的'));
  await _tapWhenReady(tester, '「我的」頁的「閱讀偏好」', find.text('閱讀偏好'));
  await _waitFor(
    tester,
    '「閱讀偏好」頁',
    () => find.byType(ReadingSettingsPage).evaluate().isNotEmpty,
  );
  await _pumpFor(tester, const Duration(seconds: 2));
  _expectNoBrokenPart('「閱讀偏好」頁');
}

/// 等 [target] 點得到（連續幾幀都在最上層），再點最後一個。
Future<void> _tapWhenReady(
  WidgetTester tester,
  String what,
  Finder target,
) async {
  final tappable = target.hitTestable();
  await _waitFor(tester, what, () => tappable.evaluate().isNotEmpty, stable: 5);
  await tester.tap(tappable.last);
}

/// 幾章短短的正文，章名照 TXT 分章認得的「第 N 章」。
String _chapters() => [
  for (var i = 1; i <= 3; i++)
    '第$i章 月下\n\n${List.filled(12, '山中有月，照見歸人，夜裡讀書的人抬頭看了一眼。').join()}\n',
].join('\n');

bool _veilLifted() => find
    .byType(LoadingVeil)
    .evaluate()
    .every((e) => !(e.widget as LoadingVeil).controller.isVisible);

/// 每 100 毫秒畫一幀，等到 [done] 連續 [stable] 次成立；每一步都確認畫面上沒有
/// 「這部分無法顯示」。等不到時印出畫面上的字，看是停在哪一頁。
Future<void> _waitFor(
  WidgetTester tester,
  String what,
  bool Function() done, {
  int stable = 1,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  var streak = 0;
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    _expectNoBrokenPart(what);
    streak = done() ? streak + 1 : 0;
    if (streak >= stable) return;
  }
  fail('等不到$what（${timeout.inSeconds} 秒）。畫面上的字：${_visibleTexts()}');
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _expectNoBrokenPart(String where) {
  final broken = find.textContaining('這部分無法顯示');
  if (broken.evaluate().isEmpty) return;
  fail('等$where時畫面出現「這部分無法顯示」：${_visibleTexts()}');
}

String _visibleTexts() => find
    .byWidgetPredicate((widget) => widget is Text)
    .evaluate()
    .map(
      (e) =>
          (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText(),
    )
    .whereType<String>()
    .where((text) => text.trim().isNotEmpty)
    .take(40)
    .join('、');

/// 系統的選檔畫面換成直接交出 [path]。
class _PickOneFile extends FilePickerPlatform {
  _PickOneFile(this.path);

  final String path;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
  }) async => FilePickerResult([
    PlatformFile(
      path: path,
      name: p.basename(path),
      size: File(path).lengthSync(),
    ),
  ]);
}
