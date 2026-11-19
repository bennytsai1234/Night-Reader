// 找出檔名和裡面的公開型別對不上的檔：檔名該是主要類別名稱的小寫寫法
// （CODING_STANDARDS.md「命名」）。
//
//   dart run tool/file_names.dart            看 lib/ 底下
//   dart run tool/file_names.dart lib/core   只看某個資料夾
//
// 檔裡任何一個公開的 class、enum、mixin、extension、extension type 或 typedef，
// 名稱以檔名開頭（`glass.dart` 裡的 `GlassSurface`），或檔名以它的名稱開頭
// （`reader_page_shell.dart` 裡的 `ReaderPage`），而且切在詞的交界
// （`user.dart` 裡的 `UsernameDialog` 不算），就算對得上；比對時不看底線
// 與大小寫（`webdav_sync_store.dart` 和 `WebDavSyncStore` 一樣）。註解與字串
// 裡的字不算宣告。沒有公開型別的檔、產生的 `.g.dart` 與 `part of` 的檔不看。
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
  r'(?:class|enum|mixin|typedef|extension\s+type|extension(?!\s+on\b))'
  r'\s+([A-Za-z]\w*)',
  multiLine: true,
);

/// 檔名 [base]（不含 `.dart`）和 [text] 裡的公開型別對不上時，回傳那些型別；
/// 對得上、沒有公開型別或是 `part of` 的檔，回傳 null。
List<String>? fileNameMismatch(String base, String text) {
  final code = _blankCommentsAndStrings(text);
  if (RegExp(r'^part\s+of\b', multiLine: true).hasMatch(code)) return null;
  final types = _declaration
      .allMatches(code)
      .map((m) => m[1]!)
      .where((name) => !name.startsWith('_'))
      .toList();
  if (types.isEmpty || types.any((type) => _matches(base, type))) return null;
  return types;
}

/// 前綴要切在詞的交界：型別名稱的下一個字是大寫，或檔名的下一個字是底線；
/// 檔名多一個複數的 s 也算（`sync_records.dart` 裡的 `SyncRecord`）。
bool _matches(String base, String type) {
  final file = base.replaceAll('_', '');
  final name = type.toLowerCase();
  if (name == file) return true;
  if (name.startsWith(file)) {
    final next = type[file.length];
    return next != next.toLowerCase();
  }
  if (!file.startsWith(name)) return false;
  var i = 0;
  for (var letters = 0; letters < name.length; i++) {
    if (base[i] != '_') letters++;
  }
  final rest = base.substring(i);
  return rest.startsWith('_') || rest == 's' || rest.startsWith('s_');
}

/// 把註解與字串的內容換成空白、保留換行，宣告的比對才不會讀到註解或字串裡
/// 的 `class`。
String _blankCommentsAndStrings(String text) {
  final out = StringBuffer();
  var i = 0;
  void blank(int end) {
    for (; i < end && i < text.length; i++) {
      out.write(text[i] == '\n' ? '\n' : ' ');
    }
  }

  bool at(String s) => text.startsWith(s, i);

  // 掃一段程式碼，遇到 [untilBrace] 層級的 `}` 就停（字串插值的結尾）。
  void code({bool untilBrace = false}) {
    var depth = 0;
    while (i < text.length) {
      if (at('//')) {
        final end = text.indexOf('\n', i);
        blank(end < 0 ? text.length : end);
      } else if (at('/*')) {
        var nest = 0;
        final from = i;
        var j = i;
        while (j < text.length) {
          if (text.startsWith('/*', j)) {
            nest++;
            j += 2;
          } else if (text.startsWith('*/', j)) {
            nest--;
            j += 2;
            if (nest == 0) break;
          } else {
            j++;
          }
        }
        i = from;
        blank(j);
      } else if (at("'") ||
          at('"') ||
          ((at("r'") || at('r"')) &&
              (i == 0 || !RegExp(r'\w').hasMatch(text[i - 1])))) {
        final raw = text[i] == 'r';
        if (raw) blank(i + 1);
        final quote = text.startsWith(text[i] * 3, i) ? text[i] * 3 : text[i];
        blank(i + quote.length);
        while (i < text.length && !at(quote)) {
          if (!raw && at(r'\')) {
            blank(i + 2);
          } else if (!raw && at(r'${')) {
            blank(i + 2);
            code(untilBrace: true);
            blank(i + 1);
          } else if (quote.length == 1 && text[i] == '\n') {
            break;
          } else {
            blank(i + 1);
          }
        }
        blank(i + quote.length);
      } else {
        final c = text[i];
        if (untilBrace) {
          if (c == '{') depth++;
          if (c == '}') {
            if (depth == 0) return;
            depth--;
          }
        }
        out.write(c);
        i++;
      }
    }
  }

  code();
  return out.toString();
}

/// 把命令列給的路徑換成 repo 相對、正斜線、不帶 `./` 與結尾斜線的寫法，
/// 和 [_reviewed] 的鍵同一套。
String repoRelative(String path, {String? root}) {
  var p = path.replaceAll(r'\', '/');
  final r = (root ?? Directory.current.path).replaceAll(r'\', '/');
  final absolute = p.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(p);
  if (absolute && p.toLowerCase().startsWith('${r.toLowerCase()}/')) {
    p = p.substring(r.length + 1);
  }
  while (p.startsWith('./')) {
    p = p.substring(2);
  }
  while (p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/// [path] 在 [root] 這個資料夾底下（以目錄為界，`lib/core_extra` 不在 `lib/core`）。
bool isUnder(String path, String root) =>
    path == root || path.startsWith('$root/');

void main(List<String> args) {
  final roots = (args.isEmpty ? ['lib'] : args).map(repoRelative).toList();
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
      final path = repoRelative(file.path);
      if (_reviewed.containsKey(path)) continue;
      final base = file.uri.pathSegments.last.replaceAll('.dart', '');
      final types = fileNameMismatch(base, file.readAsStringSync());
      if (types == null) continue;
      stdout.writeln('$path\t${types.join(' ')}');
      found++;
    }
  }
  for (final path in _reviewed.keys) {
    if (!File(path).existsSync() && roots.any((r) => isUnder(path, r))) {
      stdout.writeln('$path\t看過的清單裡有，但檔案不在了：從清單拿掉');
      found++;
    }
  }
  if (found > 0) {
    stderr.writeln('$found 個檔要看：改檔名，或加進 tool/file_names.dart 看過的清單');
    exitCode = 1;
  }
}
