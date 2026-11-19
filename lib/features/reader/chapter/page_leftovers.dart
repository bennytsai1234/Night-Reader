/// 網站把別處分好幾頁的章節整章轉貼時，留在正文裡的頁碼與換頁提示（ADR
/// 0071）：「(第1/2页)」「第(1/2)页」這類頁碼、「（本章未完，请点击下一页继续
/// 阅读）」這類提示，以及換頁處再寫一次的章名。拿掉後只剩空白或章名的行整行
/// 拿掉；同一行還有正文的，只拿掉那幾個字。
///
/// 樣式照書源作者在正文規則裡常濾的寫法（2026-11-18 從 589 個書源整理），簡繁
/// 都收；廣告與網址這類別的雜訊不在這裡處理。
String removePageLeftovers(String content, {required String chapterTitle}) {
  if (!_hint.hasMatch(content)) return content;
  final title = _squash(chapterTitle);
  final kept = <String>[];
  for (final line in content.split('\n')) {
    final cleaned = line
        .replaceAll(_unfinishedNote, '')
        .replaceAll(_bracketedPageNumber, '')
        .replaceFirst(_trailingPageNumber, '');
    if (cleaned == line) {
      kept.add(line);
      continue;
    }
    // 插圖的記號（私用區的字）不算字：只剩章名與插圖的行留下插圖。
    final illustrations = cleaned.replaceAll(_notIllustration, '');
    final rest = _squash(cleaned.replaceAll(_illustration, ''));
    if (rest.isEmpty || rest == title) {
      if (illustrations.isNotEmpty) kept.add(illustrations);
      continue;
    }
    kept.add(cleaned);
  }
  return kept.join('\n');
}

/// 整章沒有提示也沒有「第1/」「第(1/」這樣的頁碼開頭，就不必逐行看。
final RegExp _hint = RegExp(r'本章未完|第\s*[（(]?\s*[0-9０-９]+\s*[/／]');

/// 插圖的記號（`IllustrationMarkers.placeholder`）所在的私用區。
final RegExp _illustration = RegExp('[\uE000-\uF8FF]');
final RegExp _notIllustration = RegExp('[^\uE000-\uF8FF]');

const String _digits = r'[0-9０-９]+';

/// 「(第1/2页)」「（第 2/2 頁）」「第(1/2)页」：帶括號的頁碼，在行裡哪裡都算。
final RegExp _bracketedPageNumber = RegExp(
  '[（(]\\s*第\\s*$_digits\\s*[/／]\\s*$_digits\\s*[页頁]\\s*[）)]'
  '|第\\s*[（(]\\s*$_digits\\s*[/／]\\s*$_digits\\s*[）)]\\s*[页頁]',
);

/// 沒有括號的「第2/2页」只認行尾（章名後面接頁碼），正文裡提到的頁數不動。
final RegExp _trailingPageNumber = RegExp(
  '第\\s*$_digits\\s*[/／]\\s*$_digits\\s*[页頁]\\s*\$',
);

/// 「（本章未完，请点击下一页继续阅读）」「本章未完，点击下一页继续阅读。」：
/// 「本章未完」後面要接下一頁、翻頁或繼續閱讀才算，「本章未完待續」這類正文
/// 不動。帶括號的到括號為止，沒括號的到句末為止；長度有上限，一行裡很多個
/// 沒收尾的括號也不會一再掃到行尾。
final RegExp _unfinishedNote = RegExp(
  '[（(【\\[]\\s*本章未完[^）)】\\]\\n]{0,30}?$_turnPage[^）)】\\]\\n]{0,20}?[）)】\\]]'
  '|本章未完[^。！？!?\\n]{0,15}?$_turnPage(?:$_keepReading)?[》>\\s]*[。！？!?]?',
);

/// 叫讀者翻頁的字：下一頁、翻頁、繼續閱讀（簡繁）。
const String _turnPage = '(?:下一[页頁]|翻[页頁]|$_keepReading)';
const String _keepReading = '[继繼][续續][阅閱][读讀]';

/// 比對章名用：拿掉空白（目錄的「第7章 添加规则」對正文的「第7章添加规则」）。
String _squash(String text) => text.replaceAll(RegExp(r'\s'), '');
