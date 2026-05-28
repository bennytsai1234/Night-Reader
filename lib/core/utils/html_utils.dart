import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

/// HtmlUtils - HTML 樹處理工具 (原 Android utils/JsoupExtensions.kt)
class HtmlUtils {
  HtmlUtils._();

  /// 獲取格式化後的文本數組 (對標 Element.textArray)
  /// 會根據塊元素 (div, p, br) 自動換行
  static List<String> textArray(dom.Element element) {
    final buffer = StringBuffer();
    _traverse(element, buffer);
    final text = buffer.toString().trim();
    if (text.isEmpty) return [];
    return text.split('\n').where((s) => s.trim().isNotEmpty).toList();
  }

  static void _traverse(dom.Node node, StringBuffer buffer) {
    if (node is dom.Text) {
      buffer.write(_normaliseWhitespace(node.text));
    } else if (node is dom.Element) {
      final tag = node.localName;
      final isBlock = _isBlock(tag);

      if (buffer.isNotEmpty &&
          (isBlock || tag == 'br') &&
          !_lastCharIsWhitespace(buffer)) {
        buffer.write('\n');
      }

      for (var child in node.nodes) {
        _traverse(child, buffer);
      }

      final parentNodes = node.parent?.nodes;
      if (parentNodes != null && isBlock && !_lastCharIsWhitespace(buffer)) {
        final index = parentNodes.indexOf(node);
        if (index != -1 && index < parentNodes.length - 1) {
          final next = parentNodes[index + 1];
          if (next is dom.Text) {
            buffer.write('\n');
          }
        }
      }
    }
  }

  static String _normaliseWhitespace(String text) {
    // 簡易正規化：將多個空格轉為單個
    return text.replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _isBlock(String? tag) {
    const blockTags = {
      'p',
      'div',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'ul',
      'ol',
      'li',
      'article',
      'section',
      'header',
      'footer',
      'nav',
      'aside',
      'blockquote',
      'hr',
      'pre',
      'address',
      'dl',
      'dt',
      'dd',
    };
    return blockTags.contains(tag);
  }

  static bool _lastCharIsWhitespace(StringBuffer buffer) {
    if (buffer.isEmpty) return true;
    final last = buffer.toString().characters.last;
    return last == ' ' || last == '\n';
  }
}
