import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/japanese_translation_service.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_japanese_pass.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_processed_chapter.dart';

class _FakeTranslator implements JapaneseParagraphTranslator {
  _FakeTranslator(this.replies);

  final Map<String, String?> replies;
  final List<String> requested = <String>[];

  @override
  Future<String?> translate(String paragraph) async {
    requested.add(paragraph);
    return replies[paragraph];
  }
}

void main() {
  group('translateJapaneseParagraphs', () {
    test('只翻譯含假名段落，縮排保留、中文段落不送翻譯', () async {
      final translator = _FakeTranslator({'これは日本語の文です': '这是日语句子'});
      const processed = ReaderV2ProcessedChapter(
        displayTitle: '第一章',
        content: '　　中文段落不動。\n　　これは日本語の文です',
      );

      final result = await translateJapaneseParagraphs(
        processed,
        translator: translator,
        chineseConvertType: 0,
      );

      expect(result.content, '　　中文段落不動。\n　　这是日语句子');
      expect(result.displayTitle, '第一章');
      expect(translator.requested, ['これは日本語の文です']);
    });

    test('譯文套用排版正規化（引號/刪節號統一）', () async {
      final translator = _FakeTranslator({'そうか…と彼は言った': '“是吗…”他说'});
      const processed = ReaderV2ProcessedChapter(
        displayTitle: '',
        content: '　　そうか…と彼は言った',
      );

      final result = await translateJapaneseParagraphs(
        processed,
        translator: translator,
        chineseConvertType: 0,
      );

      expect(result.content, '　　「是吗……」他说');
    });

    test('翻譯失敗（null）保留原文，且回傳原物件', () async {
      final translator = _FakeTranslator({});
      const processed = ReaderV2ProcessedChapter(
        displayTitle: '',
        content: '　　これは日本語の文です',
      );

      final result = await translateJapaneseParagraphs(
        processed,
        translator: translator,
        chineseConvertType: 0,
      );

      expect(identical(result, processed), isTrue);
      expect(result.content, '　　これは日本語の文です');
    });

    test('全中文章節不動、不呼叫翻譯器', () async {
      final translator = _FakeTranslator({});
      const processed = ReaderV2ProcessedChapter(
        displayTitle: '',
        content: '　　第一段。\n　　第二段。',
      );

      final result = await translateJapaneseParagraphs(
        processed,
        translator: translator,
        chineseConvertType: 0,
      );

      expect(identical(result, processed), isTrue);
      expect(translator.requested, isEmpty);
    });
  });
}
