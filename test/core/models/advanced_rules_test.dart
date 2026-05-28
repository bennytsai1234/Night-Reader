import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/dict_rule.dart';
import 'package:night_reader/core/models/http_tts.dart';
import 'package:night_reader/core/models/txt_toc_rule.dart';
import 'package:night_reader/core/models/book_chapter_review.dart';

void main() {
  group('Advanced Rules and TTS Models Tests', () {
    test('DictRule serialization', () {
      final rule = DictRule(
        name: 'Google',
        urlRule: 'https://google.com?q={{key}}',
      );
      final json = rule.toJson();
      final fromJson = DictRule.fromJson(json);
      expect(fromJson.name, 'Google');
      expect(fromJson.urlRule, contains('{{key}}'));
    });

    test('HttpTTS serialization', () {
      final tts = HttpTTS(id: 123, name: 'MS Azure', url: 'https://tts.ms.com');
      final json = tts.toJson();
      final fromJson = HttpTTS.fromJson(json);
      expect(fromJson.id, 123);
      expect(fromJson.name, 'MS Azure');
    });

    test('TxtTocRule serialization', () {
      final rule = TxtTocRule(id: 456, name: 'Standard', rule: r'第[\\d+]+章');
      final json = rule.toJson();
      final fromJson = TxtTocRule.fromJson(json);
      expect(fromJson.id, 456);
      expect(fromJson.rule, contains('第'));
    });

    test('BookChapterReview serialization', () {
      final review = BookChapterReview(
        bookId: 1,
        chapterId: 2,
        summaryUrl: 'http://review.com',
      );
      final json = review.toJson();
      final fromJson = BookChapterReview.fromJson(json);
      expect(fromJson.bookId, 1);
      expect(fromJson.summaryUrl, 'http://review.com');
    });
  });
}
