import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../constant/app_pattern.dart';

/// 存著的正文裡的插圖標記 `<img src="…">`：抽出、拿掉、對應到圖檔。
abstract final class IllustrationMarkers {
  static const int _firstPlaceholder = 0xE000;

  /// 一章最多幾張圖（私用區 U+E000–U+F8FF 的字數），再多的不顯示。
  static const int maxPerChapter = 0xF8FF - _firstPlaceholder + 1;

  /// 轉換正文時代替第 [index] 張圖的字（私用區，每張不同）：繁簡轉換與排版
  /// 整理不動它，替換規則刪掉或搬動某張圖時，其他圖照樣對得上；轉完再拿
  /// 掉、記下位置（閱讀器的 `ReaderV2Content.fromRaw`）。
  static String placeholder(int index) =>
      String.fromCharCode(_firstPlaceholder + index);

  /// [codeUnit] 是 [count] 張圖裡第幾張的記號；不是時回傳 null。
  static int? placeholderIndex(int codeUnit, int count) {
    final index = codeUnit - _firstPlaceholder;
    return index >= 0 && index < count ? index : null;
  }

  /// [raw] 裡第 i 個標記換成 [placeholder]`(i)`，回傳換好的字與依序的網址。
  /// 原文裡本來就有、和記號同一個字的先拿掉。
  static ({String text, List<String> sources}) extract(String raw) {
    if (!raw.contains('<img')) return (text: raw, sources: const []);
    final markers = [
      for (final match in AppPattern.imgPattern.allMatches(raw))
        (match: match, src: match.group(1)?.trim() ?? ''),
    ];
    final count = math.min(
      markers.where((marker) => marker.src.isNotEmpty).length,
      maxPerChapter,
    );
    String clean(String text) => String.fromCharCodes(
      text.codeUnits.where((unit) => placeholderIndex(unit, count) == null),
    );
    final sources = <String>[];
    final text = StringBuffer();
    var cursor = 0;
    for (final (:match, :src) in markers) {
      text.write(clean(raw.substring(cursor, match.start)));
      cursor = match.end;
      if (src.isEmpty || sources.length == count) continue;
      text.write(placeholder(sources.length));
      sources.add(src);
    }
    text.write(clean(raw.substring(cursor)));
    return (text: text.toString(), sources: sources);
  }

  /// 拿掉 [raw] 裡所有的標記（匯出、書源校驗、只要字的地方）。
  static String strip(String raw) {
    if (!raw.contains('<img')) return raw;
    return raw.replaceAll(AppPattern.imgPattern, '');
  }

  /// [raw] 裡依序的圖片網址。
  static List<String> sourcesOf(String raw) {
    if (!raw.contains('<img')) return const [];
    return [
      for (final match in AppPattern.imgPattern.allMatches(raw))
        if (match.group(1)?.trim() case final src? when src.isNotEmpty) src,
    ];
  }
}

/// 從圖檔開頭讀出寬高（PNG、JPEG、GIF、WebP、BMP），不解碼整張圖。
/// 讀不到或不是這幾種時回傳 null。
abstract final class ImageSize {
  static const int _headerBytes = 64 * 1024;

  static ({int width, int height})? ofFile(String path) {
    final file = File(path);
    RandomAccessFile? handle;
    try {
      if (!file.existsSync()) return null;
      handle = file.openSync();
      final length = handle.lengthSync();
      final head = handle.readSync(
        length < _headerBytes ? length : _headerBytes,
      );
      final size = ofBytes(head);
      if (size != null || length <= _headerBytes) return size;
      // JPEG 的尺寸可能在很大的 EXIF 之後，讀整個檔再找一次。
      handle.setPositionSync(0);
      return ofBytes(handle.readSync(length));
    } on FileSystemException {
      return null;
    } finally {
      handle?.closeSync();
    }
  }

  static ({int width, int height})? ofBytes(Uint8List b) {
    final size = _png(b) ?? _gif(b) ?? _jpeg(b) ?? _webp(b) ?? _bmp(b);
    if (size == null || size.width <= 0 || size.height <= 0) return null;
    return size;
  }

  static int _be16(Uint8List b, int i) => (b[i] << 8) | b[i + 1];
  static int _le16(Uint8List b, int i) => b[i] | (b[i + 1] << 8);
  static int _be32(Uint8List b, int i) =>
      (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
  static int _le32(Uint8List b, int i) =>
      b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);

  static ({int width, int height})? _png(Uint8List b) {
    if (b.length < 24 ||
        b[0] != 0x89 ||
        b[1] != 0x50 ||
        b[2] != 0x4E ||
        b[3] != 0x47) {
      return null;
    }
    return (width: _be32(b, 16), height: _be32(b, 20));
  }

  static ({int width, int height})? _gif(Uint8List b) {
    if (b.length < 10 || b[0] != 0x47 || b[1] != 0x49 || b[2] != 0x46) {
      return null;
    }
    return (width: _le16(b, 6), height: _le16(b, 8));
  }

  static ({int width, int height})? _bmp(Uint8List b) {
    if (b.length < 26 || b[0] != 0x42 || b[1] != 0x4D) return null;
    final height = _le32(b, 22).toSigned(32).abs();
    return (width: _le32(b, 18).toSigned(32).abs(), height: height);
  }

  static ({int width, int height})? _webp(Uint8List b) {
    if (b.length < 30 ||
        String.fromCharCodes(b.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(b.sublist(8, 12)) != 'WEBP') {
      return null;
    }
    final chunk = String.fromCharCodes(b.sublist(12, 16));
    switch (chunk) {
      case 'VP8 ':
        return (width: _le16(b, 26) & 0x3FFF, height: _le16(b, 28) & 0x3FFF);
      case 'VP8L':
        final bits = _le32(b, 21);
        return (
          width: (bits & 0x3FFF) + 1,
          height: ((bits >> 14) & 0x3FFF) + 1,
        );
      case 'VP8X':
        return (
          width: (b[24] | (b[25] << 8) | (b[26] << 16)) + 1,
          height: (b[27] | (b[28] << 8) | (b[29] << 16)) + 1,
        );
    }
    return null;
  }

  static ({int width, int height})? _jpeg(Uint8List b) {
    if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i += 1;
        continue;
      }
      final marker = b[i + 1];
      if (marker == 0xFF) {
        i += 1;
        continue;
      }
      // SOF0–SOF15，排除 DHT（C4）、JPG（C8）、DAC（CC）。
      if (marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        return (width: _be16(b, i + 7), height: _be16(b, i + 5));
      }
      if (marker == 0xD8 ||
          (marker >= 0xD0 && marker <= 0xD7) ||
          marker == 0x01) {
        i += 2;
        continue;
      }
      i += 2 + _be16(b, i + 2);
    }
    return null;
  }
}
