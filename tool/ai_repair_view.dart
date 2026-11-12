// 把一份 AI 修復的完整紀錄（.txt）轉成可以點開看的 HTML：每一步一張卡片，
// 每一輪收起來時看得到 AI 下的指令與這輪的用量，點開看送給 AI 的話、AI 的
// 思考、回覆與夜讀做的事。
//
//   dart run tool/ai_repair_view.dart <紀錄.txt> <輸出.html>
//
// 紀錄是手機「分享完整紀錄」的檔，或 test/live/source_repair_batch_live_test.dart
// 跑完印出的 ai-repair/ 資料夾裡的檔。
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('用法：dart run tool/ai_repair_view.dart <紀錄.txt> <輸出.html>');
    exitCode = 64;
    return;
  }
  final lines = File(args[0]).readAsLinesSync();
  File(args[1]).writeAsStringSync(render(lines));
}

/// 段落的標題：`## 第 3 輪（+0:06）` 這種，結尾是從修復開始算的時間。送給
/// AI 的話裡也有 `## 怎麼查` 這類小標題，不算。
final RegExp _section = RegExp(r'^## (.*（\+\d+:\d\d）)$');
final RegExp _part = RegExp(r'^### ((送給 AI|AI 的思考|AI 回覆|請求與網站回的原文|程式).*)$');
final RegExp _usage = RegExp(
  r'AI 回覆 ([\d.]+) 秒.*?送出 ([\d,]+) token（打中快取 ([\d,]+)）、回覆 ([\d,]+)（思考 ([\d,]+)）',
);
final RegExp _event = RegExp(
  r'^(看網頁|讀頁|在頁|解析頁|跑程式|AI 改了|AI 沒改|沒有收到指令|讀不懂|AI 想放棄|AI 說修不好)',
);

const int _rawLimit = 4000;

String render(List<String> lines) {
  final title = lines.isEmpty
      ? ''
      : lines.first.replaceFirst(RegExp(r'^#\s*'), '');
  final meta = lines.length > 1 ? lines[1] : '';
  final sections = <_Section>[];
  for (final line in lines.skip(2)) {
    final section = _section.firstMatch(line);
    if (section != null) {
      sections.add(_Section(section.group(1)!));
      continue;
    }
    if (sections.isEmpty) continue;
    final part = _part.firstMatch(line);
    if (part != null) {
      sections.last.parts.add(_Part(part.group(1)!));
    } else if (sections.last.parts.isNotEmpty) {
      sections.last.parts.last.body.add(line);
    } else {
      sections.last.lead.add(line);
    }
  }
  final cards = sections.map(_card).join();
  return '''<!doctype html><html><head><meta charset="utf-8"><title>AI 修復紀錄</title>
<style>$_style</style></head><body>
<div class="head"><h2>${_esc(title)}</h2><div class="dim">${_esc(meta)}</div></div>
$cards
</body></html>''';
}

String _card(_Section section) {
  final round = section.title.startsWith('第 ');
  final lead = section.lead.where((l) => l.trim().isNotEmpty).join('\n');
  final everything = [
    lead,
    for (final part in section.parts) ...part.body,
  ].join('\n');
  final usage = _usage.firstMatch(everything);
  final pills = usage == null
      ? ''
      : '<span class="pill">AI ${usage.group(1)} 秒</span>'
            '<span class="pill">送出 ${usage.group(2)} token（快取 ${usage.group(3)}）</span>'
            '<span class="pill">回覆 ${usage.group(4)}（思考 ${usage.group(5)}）</span>';
  var gist = '';
  for (final part in section.parts) {
    if (!part.title.startsWith('AI 回覆')) continue;
    final body = part.body.join('\n');
    final action =
        RegExp(r'"action"\s*:\s*"(\w+)"').firstMatch(body) ??
        RegExp(r'invoke name="(\w+)"').firstMatch(body);
    final event = part.body.firstWhere(_event.hasMatch, orElse: () => '');
    gist =
        '${action?.group(1) ?? '沒有指令'}'
        '${event.isEmpty ? '' : '：${event.length > 70 ? event.substring(0, 70) : event}'}';
  }
  return '<details class="card ${round ? 'round' : 'step'}"${round ? '' : ' open'}>'
      '<summary><b>${_esc(section.title)}</b>'
      '${gist.isEmpty ? '' : '<span class="gist">${_esc(gist)}</span>'}$pills</summary>'
      '${lead.isEmpty ? '' : '<pre class="lead">${_esc(lead)}</pre>'}'
      '${section.parts.map(_partHtml).join()}</details>';
}

String _partHtml(_Part part) {
  final (kind, label) = switch (part.title) {
    final t when t.startsWith('送給 AI（system') => ('sys', '系統提示'),
    final t when t.startsWith('送給 AI') => ('user', '送給 AI'),
    final t when t.startsWith('AI 的思考') => ('think', 'AI 的思考'),
    final t when t.startsWith('AI 回覆') => ('reply', 'AI 回覆'),
    final t when t.startsWith('請求與網站回的原文') => ('raw', '網站回的原文'),
    _ => ('raw', '程式'),
  };
  var body = part.body.join('\n').trim();
  final size = RegExp(r'（.*?(\d+) 字）').firstMatch(part.title);
  var after = '';
  if (kind == 'reply' && size != null) {
    final n = int.parse(size.group(1)!).clamp(0, body.length);
    final rest = body.substring(n).trim();
    body = body.substring(0, n);
    if (rest.isNotEmpty) {
      after =
          '<div class="part done"><span class="tag">夜讀做的事</span>'
          '<pre>${_esc(rest)}</pre></div>';
    }
  }
  var clipped = '';
  if (kind == 'raw' && body.length > _rawLimit) {
    clipped = '\n…（共 ${body.length} 字，這裡只列前 $_rawLimit 字）';
    body = body.substring(0, _rawLimit);
  }
  final open = kind == 'reply' || kind == 'think' ? ' open' : '';
  return '<details class="part $kind"$open><summary><span class="tag">$label</span>'
      '<span class="dim">${size == null ? '' : '${size.group(1)} 字'}</span></summary>'
      '<pre>${_esc(body)}${_esc(clipped)}</pre></details>$after';
}

/// 網頁原文裡的 `src=` 與圖片路徑寫成實體字元：看的工具不會去載入它們。
String _esc(String text) => const HtmlEscape(HtmlEscapeMode.element)
    .convert(text)
    .replaceAll('src=', 'src&#61;')
    .replaceAllMapped(
      RegExp(r'\.(jpe?g|png|gif|webp|svg|avif|bmp)', caseSensitive: false),
      (m) => '&#46;${m.group(1)}',
    );

final class _Section {
  _Section(this.title);
  final String title;
  final List<String> lead = [];
  final List<_Part> parts = [];
}

final class _Part {
  _Part(this.title);
  final String title;
  final List<String> body = [];
}

const String _style = '''
:root { color-scheme: light dark; }
body { margin: 0; font-family: var(--font-sans, system-ui); color: var(--foreground, #222); }
.head { margin: 0 0 12px; }
.head h2 { font-size: 16px; margin: 0 0 4px; }
.dim { color: var(--muted-foreground, #888); font-size: 12px; margin-left: 8px; }
.card { border: 1px solid var(--border, #ddd); border-radius: var(--radius, 8px); margin: 8px 0; padding: 0 12px; background: var(--card, transparent); }
.card > summary { cursor: pointer; padding: 10px 0; font-size: 14px; display: flex; flex-wrap: wrap; gap: 6px; align-items: center; }
.card.step > summary b { color: var(--info, #36c); }
.gist { font-size: 13px; }
.pill { font-size: 11px; padding: 2px 8px; border-radius: 999px; background: var(--secondary, #eee); color: var(--secondary-foreground, #333); }
pre { white-space: pre-wrap; word-break: break-all; font-family: var(--font-mono, monospace); font-size: 12px; line-height: 1.5; margin: 6px 0 10px; padding: 8px 10px; border-radius: 6px; background: var(--code-background, #f5f5f5); max-height: 420px; overflow: auto; }
pre.lead { background: transparent; padding: 0; max-height: none; }
.part { margin: 4px 0; }
.part > summary { cursor: pointer; font-size: 12px; padding: 4px 0; }
.tag { font-weight: 600; }
.part.think .tag { color: var(--warning, #b80); }
.part.reply .tag { color: var(--success, #2a2); }
.part.user .tag { color: var(--primary, #36c); }
.part.done .tag { color: var(--info, #36c); font-size: 12px; }
.part.sys .tag, .part.raw .tag { color: var(--muted-foreground, #888); }
''';
