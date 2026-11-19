import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/request_answers.dart';

const _heading = '\n\n# 同一個請求這次回過不同的結果\n';
const _url = 'https://site.example/s';

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

  test('429 counts as a failure; another 4xx does not', () {
    final answers = RequestAnswers();
    answers.record('$_url\n  ← $_url 200');
    expect(answers.record('$_url\n  ← $_url 404'), '');
    expect(
      answers.record('$_url\n  ← $_url 429'),
      '$_heading$_url：200、404、429',
    );
  });

  group('requests that differ only in', () {
    for (final (what, first, second) in [
      ('the method', 'POST $_url', 'PUT $_url'),
      ('the body', 'POST $_url 送出：k=a', 'POST $_url 送出：k=b'),
      ('the headers', '$_url 標頭：{"a":"1"}', '$_url 標頭：{"a":"2"}'),
    ]) {
      test('$what are different requests', () {
        final answers = RequestAnswers();
        answers.record('$first\n  ← $_url 502');
        expect(answers.record('$second\n  ← $_url 200'), '');
        expect(
          answers.record('$first\n  ← $_url 200'),
          '$_heading$first：502、200',
        );
      });
    }
  });

  test('a redirect hop to the same address is a GET of it, not the POST', () {
    final answers = RequestAnswers();
    const post = 'POST $_url 送出：k=a';

    answers.record('$post\n  ← $_url 503');
    // POST 回 302 轉回同一個網址，下一跳是 GET：它的 200 不算 POST 的。
    expect(
      answers.record('$post\n  ← $_url 302\n$_url（轉址）\n  ← $_url 200'),
      '$_heading$post：503、302',
    );
    expect(answers.record('$_url\n  ← $_url 503'), '$_heading$_url：200、503');
  });

  test('an answer without its request line is ignored', () {
    final answers = RequestAnswers();
    expect(answers.record('  ← $_url 200'), '');
    expect(answers.record('  ← $_url 503'), '');
  });
}
