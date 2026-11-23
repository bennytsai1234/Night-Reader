import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';

void main() {
  final book = Book(
    bookUrl: 'https://site.test/b/1',
    origin: 'https://site.test',
  );
  BookSource source(int type) => BookSource.fromJson({
    'bookSourceUrl': 'https://site.test',
    'bookSourceName': '站',
    'bookSourceType': type,
  });

  test('comic content is counted in pictures, audio in links, novels in '
      'characters', () {
    final pictures = [
      for (var i = 1; i <= 3; i++) '<img src="https://img.test/$i.jpg">',
    ].join('\n');
    expect(contentAmountText(source(2), book, pictures), '3 張圖');
    expect(
      contentAmountText(
        source(1),
        book,
        'https://a.test/1.mp3\nhttps://a.test/2.m4a',
      ),
      '2 個音訊網址',
    );
    expect(contentAmountText(source(0), book, '第一章' * 100), isNull);
  });

  test('the probe summary says pictures instead of the characters of the '
      'image tags', () {
    const logs = [(1000, '內容長度: 6315')];
    expect(
      const SourceProbeReport(
        logs: logs,
        requests: [],
        contentUsable: true,
        contentAmount: '54 張圖',
      ).summary,
      '正文 54 張圖',
    );
    expect(
      const SourceProbeReport(
        logs: logs,
        requests: [],
        contentUsable: true,
      ).summary,
      '正文 6315 字',
    );
  });
}
