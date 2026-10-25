import 'package:html/dom.dart' as dom;

/// Jsoup 的 `Element.text()`：空白縮成一格、頭尾去掉；區塊元素的前後與
/// `<br>` 處補一個空格（`<p>甲</p><p>乙</p>` 是「甲 乙」）；`<pre>`、
/// `<textarea>` 裡的空白照原樣；`<script>`、`<style>` 的內容不算文字。
String jsoupText(dom.Node node) {
  final buffer = StringBuffer();
  void visit(dom.Node current) {
    switch (current) {
      case dom.Text():
        _appendNormalised(buffer, current);
      case dom.Element():
        final tag = current.localName ?? '';
        if (buffer.isNotEmpty &&
            (_blockTags.contains(tag) || tag == 'br') &&
            !_endsWithSpace(buffer)) {
          buffer.write(' ');
        }
        if (_dataTags.contains(tag)) break;
        for (final child in current.nodes) {
          visit(child);
        }
        final next = _nextSibling(current);
        if (_blockTags.contains(tag) &&
            (next is dom.Text ||
                (next is dom.Element &&
                    !_blockTags.contains(next.localName))) &&
            !_endsWithSpace(buffer)) {
          buffer.write(' ');
        }
      default:
        for (final child in current.nodes) {
          visit(child);
        }
    }
  }

  if (node is dom.Text) {
    _appendNormalised(buffer, node);
  } else {
    for (final child in node.nodes) {
      visit(child);
    }
  }
  return buffer.toString().trim();
}

/// Jsoup 的 `Element.ownText()`：只有自己底下的文字，`<br>` 算一個空格。
String jsoupOwnText(dom.Node node) {
  final buffer = StringBuffer();
  for (final child in node.nodes) {
    if (child is dom.Text) {
      _appendNormalised(buffer, child);
    } else if (child is dom.Element &&
        child.localName == 'br' &&
        !_endsWithSpace(buffer)) {
      buffer.write(' ');
    }
  }
  return buffer.toString().trim();
}

void _appendNormalised(StringBuffer buffer, dom.Text text) {
  final value = text.data;
  if (_preservesWhitespace(text.parentNode)) {
    buffer.write(value);
    return;
  }
  var lastWasSpace = _endsWithSpace(buffer);
  for (final rune in value.runes) {
    if (_isWhitespace(rune)) {
      if (!lastWasSpace) {
        buffer.write(' ');
        lastWasSpace = true;
      }
    } else if (rune != 0x200B && rune != 0xAD) {
      buffer.writeCharCode(rune);
      lastWasSpace = false;
    }
  }
}

dom.Node? _nextSibling(dom.Node node) {
  final siblings = node.parentNode?.nodes;
  if (siblings == null) return null;
  final index = siblings.indexOf(node) + 1;
  return index < siblings.length ? siblings[index] : null;
}

/// Jsoup 往上看六層，有 `<pre>` 這類保留空白的元素就照原樣。
bool _preservesWhitespace(dom.Node? node) {
  var current = node;
  for (var depth = 0; depth < 6 && current != null; depth++) {
    if (current is dom.Element && _preserveTags.contains(current.localName)) {
      return true;
    }
    current = current.parentNode;
  }
  return false;
}

bool _endsWithSpace(StringBuffer buffer) {
  if (buffer.isEmpty) return false;
  final text = buffer.toString();
  return text.codeUnitAt(text.length - 1) == 0x20;
}

bool _isWhitespace(int rune) =>
    rune == 0x20 ||
    rune == 0x09 ||
    rune == 0x0A ||
    rune == 0x0C ||
    rune == 0x0D ||
    rune == 0xA0;

const Set<String> _preserveTags = {'pre', 'plaintext', 'title', 'textarea'};
const Set<String> _dataTags = {'script', 'style'};

/// Jsoup `Tag` 的區塊元素。
const Set<String> _blockTags = {
  'html',
  'head',
  'body',
  'frameset',
  'script',
  'noscript',
  'style',
  'meta',
  'link',
  'title',
  'frame',
  'noframes',
  'section',
  'nav',
  'aside',
  'hgroup',
  'header',
  'footer',
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'ul',
  'ol',
  'pre',
  'div',
  'blockquote',
  'hr',
  'address',
  'figure',
  'figcaption',
  'form',
  'fieldset',
  'ins',
  'del',
  'dl',
  'dt',
  'dd',
  'li',
  'table',
  'caption',
  'thead',
  'tfoot',
  'tbody',
  'colgroup',
  'col',
  'tr',
  'th',
  'td',
  'video',
  'audio',
  'canvas',
  'details',
  'menu',
  'plaintext',
  'template',
  'article',
  'main',
  'svg',
  'math',
  'center',
  'dir',
  'applet',
  'marquee',
  'listing',
};
