import 'package:html/dom.dart' as dom;

/// Jsoup 的 `Element.text()`：空白縮成一格、頭尾去掉；區塊元素的前後與
/// `<br>` 處補一個空格（`<p>甲</p><p>乙</p>` 是「甲 乙」）；`<pre>`、
/// `<textarea>` 裡的空白照原樣；`<script>`、`<style>` 的內容是資料、不算
/// 文字（取它們自己的 text 也是空的，內容用 `data()`）。對照 Jsoup 1.15.3。
String jsoupText(dom.Node node) {
  if (_isDataElement(node)) return '';
  final writer = _TextWriter();
  if (node is dom.Text) {
    writer.appendNormalised(node);
  } else {
    _visitChildren(node, writer);
  }
  return writer.toString().trim();
}

void _visitChildren(dom.Node parent, _TextWriter writer) {
  final children = parent.nodes;
  for (var i = 0; i < children.length; i++) {
    final child = children[i];
    switch (child) {
      case dom.Text():
        writer.appendNormalised(child);
      case dom.Element():
        final tag = child.localName ?? '';
        final isBlock = _blockTags.contains(tag);
        if (writer.isNotEmpty && (isBlock || tag == 'br')) writer.space();
        if (!_dataTags.contains(tag)) _visitChildren(child, writer);
        if (isBlock && i + 1 < children.length) {
          final next = children[i + 1];
          if (next is dom.Text ||
              (next is dom.Element && !_blockTags.contains(next.localName))) {
            writer.space();
          }
        }
      default:
        _visitChildren(child, writer);
    }
  }
}

/// Jsoup 的 `Element.ownText()`：只有自己底下的文字，`<br>` 算一個空格。
String jsoupOwnText(dom.Node node) {
  if (_isDataElement(node)) return '';
  final writer = _TextWriter();
  for (final child in node.nodes) {
    if (child is dom.Text) {
      writer.appendNormalised(child);
    } else if (child is dom.Element && child.localName == 'br') {
      writer.space();
    }
  }
  return writer.toString().trim();
}

/// Jsoup 的 `Element.wholeText()`：文字照原樣不整理空白，`<br>` 換成
/// 換行；`<script>`、`<style>` 的內容不算。
String jsoupWholeText(dom.Node node) {
  if (_isDataElement(node)) return '';
  final buffer = StringBuffer();
  void visit(dom.Node current) {
    for (final child in current.nodes) {
      switch (child) {
        case dom.Text():
          buffer.write(child.data);
        case dom.Element():
          final tag = child.localName ?? '';
          if (tag == 'br') {
            buffer.write('\n');
          } else if (!_dataTags.contains(tag)) {
            visit(child);
          }
        default:
          visit(child);
      }
    }
  }

  if (node is dom.Text) return node.data;
  visit(node);
  return buffer.toString();
}

/// Jsoup `Element.isBlock()`：[tag] 是不是 Jsoup 的區塊元素。
bool jsoupIsBlock(String tag) => _blockTags.contains(tag);

bool _isDataElement(dom.Node node) =>
    node is dom.Element && _dataTags.contains(node.localName);

/// 一路寫一路記最後一個字是不是空格，不必每次把整段轉成字串再看。
class _TextWriter {
  final StringBuffer _buffer = StringBuffer();
  bool _endsWithSpace = false;

  bool get isNotEmpty => _buffer.isNotEmpty;

  void space() {
    if (_buffer.isEmpty || _endsWithSpace) return;
    _buffer.write(' ');
    _endsWithSpace = true;
  }

  void appendNormalised(dom.Text text) {
    final value = text.data;
    if (value.isEmpty) return;
    if (_preservesWhitespace(text.parentNode)) {
      _buffer.write(value);
      _endsWithSpace = value.codeUnitAt(value.length - 1) == 0x20;
      return;
    }
    for (final rune in value.runes) {
      if (_isWhitespace(rune)) {
        if (!_endsWithSpace && _buffer.isNotEmpty) {
          _buffer.write(' ');
          _endsWithSpace = true;
        } else if (_buffer.isEmpty) {
          // 開頭的空白之後 trim 會去掉；先記成空白，避免頭上多寫一格。
          _endsWithSpace = true;
        }
      } else if (rune != 0x200B && rune != 0xAD) {
        _buffer.writeCharCode(rune);
        _endsWithSpace = false;
      }
    }
  }

  @override
  String toString() => _buffer.toString();
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
