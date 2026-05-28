import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/async_js_rewriter.dart';
import 'package:night_reader/core/engine/js/js_rule_async_wrapper.dart';

void main() {
  group('JsRuleAsyncWrapper', () {
    test('injects return for final expression ending with semicolon', () {
      const source = '''
var first = java.ajax("http://a");
first + "-done";
''';

      final rewritten = JsRuleAsyncWrapper.injectFinalReturn(source);

      expect(rewritten, contains('return first + "-done";'));
    });

    test('wrap preserves realistic trailing-semicolon searchUrl scripts', () {
      const source = r'''
let new_url = java.get('https://bcshuku.com/e/search/index.php?keyboard='+key+'&show=title%2Cwriter%2Cbyr&searchget=1',{
    "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
    "sec-ch-ua": "\"Microsoft Edge\";v=\"143\", \"Chromium\";v=\"143\", \"Not A(Brand\";v=\"24\""
});
let url = 'https://bcshuku.com/e/search/'+ new_url.header("location");
url+'page='+page;
''';

      final rewritten = AsyncJsRewriter.rewrite(source);
      final wrapped = JsRuleAsyncWrapper.wrap(rewritten, 1);

      expect(wrapped, isNot(contains('eval(__lrRuleSrc)')));
      expect(wrapped, contains("return url+'page='+page;"));
    });

    test(
      'wrap preserves semicolon-less object assignments before final url expression',
      () {
        const source = r'''
json={"sign":"abc","keyword":key}
option={
  "method": "POST",
  "body": JSON.stringify(json)
}
url='http://api.example.com/book/search,'+JSON.stringify(option)
''';

        final wrapped = JsRuleAsyncWrapper.wrap(source, 3);

        expect(
          wrapped,
          contains(
            "return url='http://api.example.com/book/search,'+JSON.stringify(option);",
          ),
        );
      },
    );

    test('wrap preserves multiline method chains after bare result line', () {
      const source = r'''
result
.replace("••","")
.replace(/^(\d+).第/,'第')
''';

      final wrapped = JsRuleAsyncWrapper.wrap(source, 4);

      expect(
        wrapped,
        contains(
          "return result\n      .replace(\"••\",\"\")\n      .replace(/^(\\d+).第/,'第');",
        ),
      );
    });

    test(
      'wrap preserves realistic content scripts with regex literal and java.post',
      () {
        const source = r'''
var regex = /\{"url"\s*:\s*"[^"]+"\s*,\s*"mobile"\s*:\s*"\d"\s*,\s*"isk"\s*:\s*"\d"\s*,\s*"novel"\s*:\s*"\d+"\s*,\s*"chapter"\s*:\s*"\d+"\}/;
var match = result.match(regex);
java.log("refer = " );
java.log(baseUrl);

if (match) {
    try {
        var jsonObj = JSON.parse(match[0]);
        var params = "url=" + encodeURIComponent(jsonObj.url) +
                     "&mobile=" + encodeURIComponent(jsonObj.mobile) +
                     "&isk=" + encodeURIComponent(jsonObj.isk) +
                     "&novel=" + encodeURIComponent(jsonObj.novel) +
                     "&chapter=" + encodeURIComponent(jsonObj.chapter);
        java.log(params);

        let response = java.post("https://bcshuku.com/conapi.php", params, {
    "accept": "application/json, text/javascript, */*; q=0.01",
    "accept-language": "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6",
    "cache-control": "no-cache",
    "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
    "origin": "https://bcshuku.com",
    "pragma": "no-cache",
    "priority": "u=1, i",
    "referer": baseUrl,
    "sec-ch-ua": "\"Microsoft Edge\";v=\"143\", \"Chromium\";v=\"143\", \"Not A(Brand\";v=\"24\"",
    "sec-ch-ua-mobile": "?0",
    "sec-ch-ua-platform": "\"Windows\"",
    "sec-fetch-dest": "empty",
    "sec-fetch-mode": "cors",
    "sec-fetch-site": "same-origin",
    "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0",
    "x-requested-with": "XMLHttpRequest"
});
        if (response && response.body()) {
            var content = JSON.parse(response.body())["content"];
            java.log(content);
        } else {
            java.log("响应体为空");
        }
    } catch (e) {
        java.log("运行异常: " + e.message);
    }
} else {
    java.log("未匹配到目标 JSON 字符串");
}
''';

        final rewritten = AsyncJsRewriter.rewrite(source);
        final wrapped = JsRuleAsyncWrapper.wrap(rewritten, 2);

        expect(
          rewritten,
          contains(
            '(await java.post("https://bcshuku.com/conapi.php", params, {',
          ),
        );
        expect(wrapped, isNot(contains('eval(__lrRuleSrc)')));
        expect(wrapped, contains('return java.log(content);'));
        expect(wrapped, contains('return java.log("未匹配到目标 JSON 字符串");'));
      },
    );
  });
}
