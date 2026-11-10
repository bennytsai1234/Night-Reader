import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/network/page_digest.dart';

void main() {
  test('a page keeps its structure and text, without head, scripts and '
      'styling', () {
    final page =
        '''
<!DOCTYPE html><html><head><title>站名</title><style>.a{color:red}</style>
<script src="x.js"></script></head>
<body><!-- 廣告 --><div class="list" id="books" style="margin:0" data-x="1">
  <a href="/b/1" onclick="go()" target="_blank">書名</a>
  <img src="data:image/png;base64,${'A' * 300}" alt="封面"/>
  <script>var tracking = 1;</script><svg><path d="M0"/></svg>
</div></body></html>''';

    final digest = digestPage(page);

    expect(digest, isNot(contains('站名')));
    expect(digest, isNot(contains('tracking')));
    expect(digest, isNot(contains('廣告')));
    expect(digest, isNot(contains('style=')));
    expect(digest, isNot(contains('<path')));
    expect(digest, contains('<div class="list" id="books">'));
    expect(digest, contains('<a href="/b/1" onclick="go()">書名</a>'));
    expect(digest, contains('…"/>'), reason: '內嵌圖片只留開頭');
  });

  test('JSON and plain text stay as they are, spaces collapsed', () {
    expect(digestPage('{"a":  [1,\n 2]}'), '{"a": [1, 2]}');
    expect(digestPage('  第一章\n\n內容  '), '第一章 內容');
  });
}
