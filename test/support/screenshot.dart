// 給使用者看畫面用的截圖工具：把元件測試畫出來的畫面存成 PNG。
//
// 本機不建置 App，要讓使用者看介面時，在 `test/_screens/`（git 忽略）寫一個
// 臨時測試：
//
//   setUpAll(loadScreenshotFonts);
//   testWidgets('about', (tester) async {
//     setUpScreenshot(tester);
//     await tester.pumpWidget(MaterialApp(theme: ..., home: const AboutPage()));
//     await tester.pumpAndSettle();
//     await saveScreenshot(tester, 'about_light');
//   });
//
// 用 `flutter test test/_screens/<檔名>_test.dart` 跑，圖檔寫在
// [screenshotDir]（系統暫存區，不在 repo 裡）。看完把臨時測試刪掉：pre-push
// hook 跑全套測試時也會跑到這個資料夾。
//
// 要拍整個 App（記憶體資料庫加假的書與書源）的固定一組畫面、改介面前後
// 對照，用 `test/screens/app_screens_test.dart`（用法寫在該檔檔頭）。
//
// 中文用系統字型代替手機字型，字形會跟手機略有不同；網路圖片在測試裡不會載入。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 截圖輸出的資料夾。
final Directory screenshotDir = Directory(
  '${Directory.systemTemp.path}${Platform.pathSeparator}night-reader-screens',
);

const _cjkFontCandidates = <List<String>>[
  ['C:/Windows/Fonts/msjh.ttc', 'C:/Windows/Fonts/msjhbd.ttc'],
  [
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
  ],
];

/// 載入真的字型，取代測試預設把每個字畫成方塊的字型。放在 `setUpAll`。
///
/// - 介面預設字族（Roboto）與正文回退字族（sans-serif）：系統的中文字型。
/// - 正文標點字型：App 內建的 `assets/fonts/NightReaderPunct-*.ttf`。
/// - 圖示：Flutter SDK 內附的 Material Icons。
Future<void> loadScreenshotFonts() async {
  final cjk = _cjkFontCandidates.firstWhere(
    (paths) => File(paths.first).existsSync(),
    orElse: () => throw StateError(
      '找不到中文字型，試過：${_cjkFontCandidates.map((p) => p.first).join('、')}',
    ),
  );
  final existing = cjk.where((path) => File(path).existsSync()).toList();
  await _loadFont('Roboto', existing);
  for (final family in kReaderV2FontFamilyFallback) {
    await _loadFont(family, existing);
  }
  await _loadFont(kReaderV2PunctFontFamily, [
    'assets/fonts/NightReaderPunct-Regular.ttf',
    'assets/fonts/NightReaderPunct-Bold.ttf',
  ]);

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    // Windows 的 SDK 是小寫檔名，Linux 的是大寫；Linux 分大小寫。
    final icons = [
      'materialicons-regular.otf',
      'MaterialIcons-Regular.otf',
    ].map((name) => '$flutterRoot/bin/cache/artifacts/material_fonts/$name');
    await _loadFont('MaterialIcons', [
      icons.firstWhere(
        (path) => File(path).existsSync(),
        orElse: () => icons.first,
      ),
    ]);
  }
}

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    loader.addFont(
      Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
    );
  }
  await loader.load();
}

/// 把測試畫面設成手機尺寸（預設 393×852 邏輯像素、3 倍），並讓 path_provider
/// 指向這個測試自己的空資料夾，避免畫面裡用到它的元件拋錯。測試結束時
/// 還原並刪掉那個資料夾：閱讀器的換行與段落尺寸快取寫在這裡，留下來的話
/// 下一次（可能換了字型或排版程式）會照舊快取排，換行對不上。
void setUpScreenshot(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double devicePixelRatio = 3,
}) {
  tester.view.physicalSize = size * devicePixelRatio;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.reset);

  final previous = PathProviderPlatform.instance;
  final dir = Directory.systemTemp.createTempSync('night-reader-test-');
  PathProviderPlatform.instance = _TempPathProvider(dir.path);
  addTearDown(() {
    PathProviderPlatform.instance = previous;
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // 還有檔案開著（Windows）就留給系統暫存區清理。
    }
  });
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this._path);

  final String _path;

  @override
  Future<String?> getTemporaryPath() async => _path;

  @override
  Future<String?> getApplicationSupportPath() async => _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;

  @override
  Future<String?> getApplicationCachePath() async => _path;

  @override
  Future<String?> getExternalStoragePath() async => _path;
}

/// 把 [of] 所在的畫面（預設整個畫面，含對話框）存成 [dir]（預設
/// [screenshotDir]）裡的 `<name>.png`，回傳檔案。
Future<File> saveScreenshot(
  WidgetTester tester,
  String name, {
  Finder? of,
  Directory? dir,
}) async {
  var renderObject = tester.renderObject(of ?? find.byType(View).first);
  while (!renderObject.isRepaintBoundary) {
    renderObject = renderObject.parent!;
  }
  final layer = renderObject.debugLayer! as OffsetLayer;
  final folder = dir ?? screenshotDir;
  final file = File('${folder.path}${Platform.pathSeparator}$name.png');
  await tester.runAsync(() async {
    final image = await layer.toImage(renderObject.paintBounds);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await folder.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
  return file;
}
