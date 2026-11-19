// 找出檔名和裡面的公開型別對不上的檔：檔名該是主要類別名稱的小寫寫法
// （CODING_STANDARDS.md「命名」）。
//
//   dart run tool/file_names.dart            看 lib/ 底下
//   dart run tool/file_names.dart lib/core   只看某個資料夾
//
// 檔裡任何一個公開的 class、enum、mixin、extension、extension type 或 typedef，
// 名稱以檔名開頭（`glass.dart` 裡的 `GlassSurface`），或檔名以它的名稱開頭
// （`reader_page_shell.dart` 裡的 `ReaderPage`），就算對得上；比對時不看底線
// 與大小寫（`webdav_sync_store.dart` 和 `WebDavSyncStore` 一樣）。沒有公開型別
// 的檔、產生的 `.g.dart` 與 `part of` 的檔不看。
//
// 列出來的要人判斷：檔名說的不是它放的東西就改檔名；檔裡刻意放一組同類的
// 東西、或主角是函式，就加進下面的 [_reviewed] 並寫一句為什麼。有沒列進去的
// 檔對不上時結束碼是 1。
import 'dart:io';

/// 看過、刻意這樣命名的檔，和理由。
const _reviewed = {
  'lib/main.dart': 'App 的進入點',
  'lib/core/ai_find/ai_find_prompt.dart': '提示詞與 AI 可以下的各種指令',
  'lib/core/ai_repair/agent_loop.dart': 'AI 修復一回合的指令、結果與紀錄',
  'lib/core/ai_repair/ai_repair_prompt.dart': '提示詞與 AI 可以下的各種指令',
  'lib/core/database/tables/app_tables.dart': '所有資料表與欄位轉換',
  'lib/core/engine/analyze_rule/analyze_rule_support.dart': '規則解析共用的小型別',
  'lib/core/engine/js/extensions/js_blocking_tasks.dart': '規則 JS 同步等待的工作',
  'lib/core/engine/js/ttf/ttf_tables.dart': 'TTF 字型檔裡的各張表',
  'lib/core/engine/parsers/css/analyze_by_css_support.dart': 'CSS 解析共用的小型別',
  'lib/core/local_book/local_book_fingerprint.dart': '主角是算原檔指紋的函式',
  'lib/core/models/source/book_source_rules.dart': '書源搜尋、詳情、目錄、正文各段規則',
  'lib/core/network/redirects.dart': '回應的轉址換算（Response 的 extension）',
  'lib/core/source/source_progress.dart': '主角是交回書源工作進度的函式',
  'lib/features/about/privacy_pages.dart': '隱私說明與權限兩頁',
  'lib/features/bookshelf/widgets/bookshelf_book_tiles.dart': '書卡與它的各部分',
  'lib/features/comic_reader/comic_reader_menu.dart': '漫畫閱讀器選單的各部分',
  'lib/features/explore/widgets/explore_skeletons.dart': '發現頁的兩種骨架',
  'lib/features/reader/features/settings/reader_highlight_style.dart':
      '標註的顏色與深淺',
  'lib/features/reader/text_view/core/text_view_types.dart': '正文層共用的小型別',
  'lib/features/reader/text_view/view/viewport_commands.dart': '捲動視窗收的指令',
  'lib/features/settings/provider/settings_base.dart':
      '在 provider/ 底下，SettingsProviderBase',
  'lib/features/settings/sync_status_text.dart': '同步的狀態文字與進度框',
  'lib/features/source_login/source_login_form.dart': '登入表單的欄位與按鈕',
  'lib/features/source_manager/widgets/import_preview_sheet.dart':
      '主角是打開匯入預覽的函式',
  'lib/shared/theme/app_tokens.dart': '設計常數',
  'lib/shared/theme/context_ext.dart': 'BuildContext 取配色的 extension',
  'lib/shared/widgets/popups/app_dialogs.dart': '提示框與動作表',
  'lib/shared/widgets/popups/popup_routes.dart': '彈出層從哪裡打開、套什麼主題',
};

final _declaration = RegExp(
  r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
  r'(?:class|enum|mixin|typedef|extension\s+type|extension)\s+([A-Za-z]\w*)',
  multiLine: true,
);

bool _matches(String base, String type) {
  final file = base.replaceAll('_', '');
  final name = type.toLowerCase();
  return name.startsWith(file) || file.startsWith(name);
}

void main(List<String> args) {
  final roots = args.isEmpty ? ['lib'] : args;
  var found = 0;
  for (final root in roots) {
    final files =
        Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.endsWith('.g.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final path = file.path.replaceAll(r'\', '/');
      if (_reviewed.containsKey(path)) continue;
      final text = file.readAsStringSync();
      if (RegExp(r'^part of ', multiLine: true).hasMatch(text)) continue;
      final types = _declaration
          .allMatches(text)
          .map((m) => m[1]!)
          .where((name) => !name.startsWith('_'))
          .toList();
      if (types.isEmpty) continue;
      final base = file.uri.pathSegments.last.replaceAll('.dart', '');
      if (types.any((type) => _matches(base, type))) continue;
      stdout.writeln('$path\t${types.join(' ')}');
      found++;
    }
  }
  for (final path in _reviewed.keys) {
    if (!File(path).existsSync() && roots.any(path.startsWith)) {
      stdout.writeln('$path\t看過的清單裡有，但檔案不在了：從清單拿掉');
      found++;
    }
  }
  if (found > 0) {
    stderr.writeln('$found 個檔要看：改檔名，或加進 tool/file_names.dart 看過的清單');
    exitCode = 1;
  }
}
