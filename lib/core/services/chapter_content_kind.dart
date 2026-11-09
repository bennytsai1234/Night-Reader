import '../models/source/book_source_logic.dart';
import '../utils/illustration_markers.dart';

/// 這章正文對 [kind] 這類書算不算抓到了：小說要讀得到字，漫畫要有圖，有聲
/// 要有網址。書源校驗與換源都照它。
bool chapterContentUsable(BookSourceKind kind, String content) =>
    switch (kind) {
      BookSourceKind.comic => ChapterContentShape.of(content).images > 0,
      BookSourceKind.audio => ChapterContentShape.of(content).urls > 0,
      _ => chapterTextReadable(content),
    };

/// 拿掉插圖標記後還有夠多的字：整章是圖（例如把 VIP 章畫成圖的網站）不算
/// 讀得到（ADR 0050）。
bool chapterTextReadable(String content) {
  final trimmed = IllustrationMarkers.strip(content).trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.startsWith('加載章節失敗')) return false;
  if (trimmed.startsWith('章節內容為空')) return false;
  return trimmed.runes.length >= 20;
}

/// 書源校驗照抓到的一章正文判斷書源是哪一類（ADR 0051）。正文裡的圖片是
/// `<img src="網址">`（抓正文時一律留下，ADR 0050）。
///
/// 要有十足把握才給答案，判斷不出來就是 [unclear]，校驗維持書源原本的類型：
/// - 成段文字（去掉圖片與網址後至少 [_textRunes] 字）是 [text]，每章附插圖
///   的小說也是；
/// - 好幾張圖（至少 [_comicImages] 張）、幾乎沒有字（少於 [_comicMaxRunes]
///   字）是 [images]；
/// - 只有音訊連結、沒有圖、幾乎沒有字是 [audio]。
enum ChapterContentKind {
  text,
  images,
  audio,
  unclear;

  static const int _textRunes = 200;
  static const int _comicImages = 2;
  static const int _comicMaxRunes = 50;
  static const int _audioMaxRunes = 20;

  static ChapterContentKind of(String content) {
    final shape = ChapterContentShape.of(content);
    if (shape.textRunes >= _textRunes) return text;
    if (shape.images >= _comicImages && shape.textRunes < _comicMaxRunes) {
      return images;
    }
    if (shape.audioUrls > 0 &&
        shape.images == 0 &&
        shape.textRunes < _audioMaxRunes) {
      return audio;
    }
    return unclear;
  }
}

/// 一章正文裡有幾張圖、幾個網址、幾個音訊連結，去掉這些後剩幾個字。
class ChapterContentShape {
  const ChapterContentShape({
    required this.images,
    required this.urls,
    required this.audioUrls,
    required this.textRunes,
  });

  /// `<img>` 標記，加上整行只有一個圖片網址的行（有些漫畫源的正文規則直接
  /// 回傳一串網址）。
  final int images;

  /// 整行只有一個網址的行（含圖片與音訊網址）。
  final int urls;

  /// 整行只有一個音訊網址的行。
  final int audioUrls;

  /// 去掉圖片、網址與空白後的字數。
  final int textRunes;

  static final RegExp _imgTag = RegExp(r'<img\b[^>]*>', caseSensitive: false);
  static final RegExp _urlLine = RegExp(
    r'^https?://\S+$',
    caseSensitive: false,
  );
  static final RegExp _imageUrl = RegExp(
    r'\.(?:jpe?g|png|webp|gif|avif|bmp)(?:[?#,]|$)',
    caseSensitive: false,
  );
  static final RegExp _audioUrl = RegExp(
    r'\.(?:mp3|m4a|aac|ogg|oga|opus|flac|wav)(?:[?#,]|$)',
    caseSensitive: false,
  );
  static final RegExp _blank = RegExp(r'[\s　]+');

  static ChapterContentShape of(String content) {
    var images = 0;
    var urls = 0;
    var audioUrls = 0;
    var textRunes = 0;
    for (final rawLine in content.split('\n')) {
      final tags = _imgTag.allMatches(rawLine).length;
      images += tags;
      final line = rawLine.replaceAll(_imgTag, '').replaceAll(_blank, '');
      if (line.isEmpty) continue;
      if (_urlLine.hasMatch(line)) {
        urls++;
        if (_imageUrl.hasMatch(line)) images++;
        if (_audioUrl.hasMatch(line)) audioUrls++;
        continue;
      }
      textRunes += line.runes.length;
    }
    return ChapterContentShape(
      images: images,
      urls: urls,
      audioUrls: audioUrls,
      textRunes: textRunes,
    );
  }
}
