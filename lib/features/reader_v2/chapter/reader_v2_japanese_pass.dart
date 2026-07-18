import 'package:night_reader/core/engine/reader/chinese_text_converter.dart';
import 'package:night_reader/core/services/japanese_text_detector.dart';
import 'package:night_reader/core/services/japanese_translation_service.dart';

import 'reader_v2_content_transformer.dart';
import 'reader_v2_processed_chapter.dart';

/// 章節內容轉換後的日文段落翻譯 pass。
///
/// 位置契約：必須在 `ReaderV2Content.fromRaw` 之前執行（displayText 的
/// TTS/進度錨點座標系在 fromRaw 定格）；本 pass 在
/// `ReaderV2ChapterRepository._loadViaV2ContentPipeline` 的 transformer
/// 之後呼叫，滿足此契約，TTS 會直接朗讀中文譯文。
///
/// 逐段處理：剝除 `　　` 縮排前綴 → 假名偵測 → 翻譯（ML Kit 輸出簡體）
/// → 依使用者繁簡設定套 [ChineseTextConverter] → [normalizeTypography]
/// 讓譯文標點與全章格線一致 → 補回縮排。任何段落翻譯失敗保留原文。
Future<ReaderV2ProcessedChapter> translateJapaneseParagraphs(
  ReaderV2ProcessedChapter processed, {
  required JapaneseParagraphTranslator translator,
  required int chineseConvertType,
}) async {
  const indent = '　　';
  if (processed.content.isEmpty) return processed;

  final lines = processed.content.split('\n');
  final output = <String>[];
  var changed = false;
  for (final line in lines) {
    final hasIndent = line.startsWith(indent);
    final body = hasIndent ? line.substring(indent.length) : line;
    if (!looksJapanese(body)) {
      output.add(line);
      continue;
    }
    final translated = await translator.translate(body);
    if (translated == null || translated.trim().isEmpty) {
      output.add(line);
      continue;
    }
    var text = const ChineseTextConverter().convert(
      translated,
      convertType: chineseConvertType,
    );
    text = normalizeTypography(text).trim();
    if (text.isEmpty) {
      output.add(line);
      continue;
    }
    output.add(hasIndent ? '$indent$text' : text);
    changed = true;
  }
  if (!changed) return processed;
  return ReaderV2ProcessedChapter(
    displayTitle: processed.displayTitle,
    content: output.join('\n'),
    effectiveReplaceRules: processed.effectiveReplaceRules,
    sameTitleRemoved: processed.sameTitleRemoved,
  );
}
