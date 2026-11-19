import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/request_answers.dart';

const _heading = '\n\n# 同一個請求這次回過不同的結果\n';

void main() {
  test('a request that answered and later failed is listed with every '
      'answer, from then on', () {
    final answers = RequestAnswers();
    const url = 'https://site.example/s?q=x';

    expect(answers.record('$url\n  ← $url 200'), '');
    expect(answers.record('$url\n  ← 頁 3｜$url 503'), '$_heading$url：200、503');
    // 之後的結果裡沒有這個請求也不再列；又碰到時照樣列出全部。
    expect(
      answers.record('https://site.example/b\n  ← https://site.example/b 200'),
      '',
    );
    expect(answers.record('$url\n  ← $url 沒有回應'), '$_heading$url：200、503、沒有回應');
  });

  test('a different method, body or header is a different request', () {
    final answers = RequestAnswers();
    const url = 'https://site.example/s';

    answers.record('POST $url 送出：k=a\n  ← $url 502');
    expect(answers.record('POST $url 送出：k=a&submit=1\n  ← $url 200'), '');
    expect(answers.record('$url 標頭：{"User-Agent":"x"}\n  ← $url 429'), '');
    expect(
      answers.record('POST $url 送出：k=a\n  ← $url 200'),
      '${_heading}POST $url 送出：k=a：502、200',
    );
  });

  test('a redirect hop is a GET of the new address; an answer without its '
      'request is ignored', () {
    final answers = RequestAnswers();
    const from = 'https://site.example/a';
    const to = 'https://site.example/b';

    answers.record('POST $from 送出：k=a\n  ← $from 301\n$to（轉址）\n  ← $to 200');
    expect(answers.record('$to\n  ← $to 503'), '$_heading$to：200、503');
    expect(answers.record('  ← https://site.example/c 200'), '');
    expect(answers.record('  ← https://site.example/c 503'), '');
  });
}
