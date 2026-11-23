/// 正文摘錄（選字、書籤的那一句、標註畫到的字）裡的段落分隔縮成一個換行。
///
/// 正文用空一行隔開段落，摘錄照正文原樣記；清單、面板與複製、分享出去時
/// 段落之間只換一行，不空行。
String withSingleLineBreaks(String text) =>
    text.replaceAll(_paragraphBreak, '\n');

final RegExp _paragraphBreak = RegExp(r'\n{2,}');
