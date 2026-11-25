import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../diagnostics/app_log_service.dart';

import 'package:fast_gbk/fast_gbk.dart';

import 'gb18030.dart';

import 'big5.dart';

/// EncodingDetect - 簡易編碼偵測工具
/// 支援 UTF-8、UTF-16LE／BE、GBK（GB18030）與 Big5：沒標字元集時照 Legado
/// 的偵測挑一個（[getEncode]）。
class EncodingDetect {
  /// 執行安全解碼，避免崩潰 (原 Android EncodingDetect.getEncode)
  static String decode(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    return decodeWithCharset(bytes, getEncode(bytes));
  }

  /// 使用已知編碼解碼完整檔案或不含 BOM 的章節切片。
  static String decodeWithCharset(List<int> bytes, String charset) {
    if (bytes.isEmpty) return '';
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final normalized = charset.trim().toUpperCase().replaceAll('_', '-');

    try {
      if (normalized == 'UTF-16LE' || normalized == 'UTF16LE') {
        return _decodeUtf16(data, Endian.little);
      }
      if (normalized == 'UTF-16BE' || normalized == 'UTF16BE') {
        return _decodeUtf16(data, Endian.big);
      }
      if (normalized == 'UTF-16' ||
          normalized == 'UTF16' ||
          normalized == 'UNICODE') {
        // Java 的 UTF-16：有 BOM 照 BOM，沒有時當大端序。
        return _decodeUtf16(
          data,
          _hasUtf16LeBom(data) ? Endian.little : Endian.big,
        );
      }
      if (normalized == 'GB18030') return Gb18030.decode(data);
      if (normalized == 'GBK' || normalized == 'GB2312') {
        return decodeGbk(data);
      }
      if (Big5.names.contains(normalized)) return Big5.decode(data);
      final offset = _hasUtf8Bom(data) ? 3 : 0;
      return utf8.decode(data.sublist(offset), allowMalformed: true);
    } catch (_) {
      return utf8.decode(data, allowMalformed: true);
    }
  }

  /// 解 GBK：壞掉的位元組只換成一個替代字元，後面的照常解（同 Legado 的
  /// `String(bytes, charset)`）。2026-11-14 86读书的正文頁有一個孤立的
  /// 0xD0，原本整頁改用 UTF-8 解成亂碼；fast_gbk 自己的 `allowMalformed`
  /// 會把孤立位元組後面那個 `<` 一起吃掉，弄壞標籤，所以先挑出孤立的雙位元組
  /// 開頭（0x81–0xFE 後面不是 0x40–0xFE、或已經到結尾），前後分段解。
  static String decodeGbk(List<int> bytes) {
    try {
      return gbk.decode(bytes);
    } on FormatException {
      // 有壞掉的位元組才逐一挑，正常的頁面照原本的速度。
    }
    final out = StringBuffer();
    var start = 0;
    var i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b < 0x81 || b > 0xFE) {
        i++;
        continue;
      }
      final next = i + 1 < bytes.length ? bytes[i + 1] : -1;
      if (next >= 0x40 && next <= 0xFE && next != 0x7F) {
        i += 2;
        continue;
      }
      out
        ..write(gbk.decode(bytes.sublist(start, i), allowMalformed: true))
        ..writeCharCode(0xFFFD);
      start = ++i;
    }
    out.write(gbk.decode(bytes.sublist(start), allowMalformed: true));
    return out.toString();
  }

  /// 將字串編成指定格式，不附加 BOM；用於把字元索引映射回檔案位元組位置。
  static Uint8List encodeWithCharset(String text, String charset) {
    final normalized = charset.trim().toUpperCase().replaceAll('_', '-');
    if (normalized == 'UTF-16LE' || normalized == 'UTF16LE') {
      return _encodeUtf16(text, Endian.little);
    }
    if (normalized == 'UTF-16BE' || normalized == 'UTF16BE') {
      return _encodeUtf16(text, Endian.big);
    }
    if (normalized == 'UTF-16' ||
        normalized == 'UTF16' ||
        normalized == 'UNICODE') {
      // 位置換算不算 BOM：兩端的長度一樣。
      return _encodeUtf16(text, Endian.big);
    }
    if (normalized == 'GB18030') return Gb18030.encode(text);
    if (normalized == 'GBK' || normalized == 'GB2312') {
      return Uint8List.fromList(gbk.encode(text));
    }
    if (Big5.names.contains(normalized)) return Big5.encode(text);
    return Uint8List.fromList(utf8.encode(text));
  }

  static int bomLength(Uint8List bytes) {
    if (_hasUtf8Bom(bytes)) return 3;
    if (_hasUtf16LeBom(bytes) || _hasUtf16BeBom(bytes)) return 2;
    return 0;
  }

  /// 照 [charset] 解碼時要跳過的 BOM 長度：只跳過這個編碼認得的 BOM；
  /// 選錯編碼時 BOM 位元組照常解碼，章節位移才對得上正文。
  static int bomLengthFor(Uint8List bytes, String charset) {
    final normalized = charset.trim().toUpperCase().replaceAll('_', '-');
    if (normalized == 'UTF-8' || normalized == 'UTF8') {
      return _hasUtf8Bom(bytes) ? 3 : 0;
    }
    if (normalized == 'UTF-16LE' || normalized == 'UTF16LE') {
      return _hasUtf16LeBom(bytes) ? 2 : 0;
    }
    if (normalized == 'UTF-16BE' || normalized == 'UTF16BE') {
      return _hasUtf16BeBom(bytes) ? 2 : 0;
    }
    if (normalized == 'UTF-16' ||
        normalized == 'UTF16' ||
        normalized == 'UNICODE') {
      return _hasUtf16LeBom(bytes) || _hasUtf16BeBom(bytes) ? 2 : 0;
    }
    return 0;
  }

  /// 讀者選的編碼 [charset] 換成實際解碼用的名字：只寫 UTF-16 時照檔案的
  /// BOM 決定 UTF-16LE／UTF-16BE（沒有 BOM 時當大端序，同 Java 的 UTF-16）；
  /// 其他編碼照原樣。章節切片沒有 BOM，存著小端／大端才解得對。
  static String resolveCharset(Uint8List bytes, String charset) {
    final normalized = charset.trim().toUpperCase().replaceAll('_', '-');
    if (normalized == 'UTF-16' ||
        normalized == 'UTF16' ||
        normalized == 'UNICODE') {
      return _hasUtf16LeBom(bytes) ? 'UTF-16LE' : 'UTF-16BE';
    }
    return charset.trim();
  }

  /// 針對 HTML 內容偵測編碼
  static String getHtmlEncode(Uint8List bytes) {
    try {
      final content = utf8.decode(
        bytes.sublist(0, bytes.length > 8000 ? 8000 : bytes.length),
        allowMalformed: true,
      );

      // 1. 尋找 <meta charset="...">
      final charsetMatch = RegExp(
        r'''<meta\b[^>]*?\scharset\s*=\s*["']?([a-zA-Z0-9_-]+)''',
        caseSensitive: false,
      ).firstMatch(content);
      if (charsetMatch != null) {
        return charsetMatch.group(1) ?? 'UTF-8';
      }

      // 2. 尋找 <meta http-equiv="Content-Type" content="...charset=...">
      final contentTypeMatch = RegExp(
        r'content=["'
        "'"
        r']?text/html;\s*charset=([a-zA-Z0-9_-]+)["'
        "'"
        r']?',
        caseSensitive: false,
      ).firstMatch(content);
      if (contentTypeMatch != null) {
        return contentTypeMatch.group(1) ?? 'UTF-8';
      }
    } catch (e, s) {
      AppLog.put('Unexpected Error', error: e, stackTrace: s);
    }

    return getEncode(bytes);
  }

  /// 偵測位元組陣列的編碼。有 BOM 照 BOM；沒有時照 Legado 用的 ICU
  /// `CharsetDetector` 裡的五個辨識器（[_IcuGuess]），在 UTF-8、沒有 BOM 的
  /// UTF-16、GB18030 與 Big5 之間挑信心最高的。名稱照辨識器（同 Legado），
  /// GB18030 的四位元組字（emoji、少見漢字）才解得出來。
  static String getEncode(Uint8List bytes) {
    if (bytes.isEmpty) return 'UTF-8';

    // 1. 檢查 UTF-8 BOM (EF BB BF)
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return 'UTF-8';
    }

    // 2. 檢查 UTF-16 BE BOM (FE FF)
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return 'UTF-16BE';
    }

    // 3. 檢查 UTF-16 LE BOM (FF FE)
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return 'UTF-16LE';
    }

    return _IcuGuess(bytes).best();
  }

  static String _decodeUtf16(Uint8List bytes, Endian endian) {
    var offset = 0;
    if ((endian == Endian.little && _hasUtf16LeBom(bytes)) ||
        (endian == Endian.big && _hasUtf16BeBom(bytes))) {
      offset = 2;
    }
    final codeUnits = <int>[];
    while (offset + 1 < bytes.length) {
      final first = bytes[offset];
      final second = bytes[offset + 1];
      codeUnits.add(
        endian == Endian.little ? first | (second << 8) : (first << 8) | second,
      );
      offset += 2;
    }
    if (offset < bytes.length) codeUnits.add(0xFFFD);
    return String.fromCharCodes(codeUnits);
  }

  static Uint8List _encodeUtf16(String text, Endian endian) {
    final result = Uint8List(text.codeUnits.length * 2);
    var offset = 0;
    for (final codeUnit in text.codeUnits) {
      if (endian == Endian.little) {
        result[offset] = codeUnit & 0xFF;
        result[offset + 1] = codeUnit >> 8;
      } else {
        result[offset] = codeUnit >> 8;
        result[offset + 1] = codeUnit & 0xFF;
      }
      offset += 2;
    }
    return result;
  }

  static bool _hasUtf8Bom(Uint8List bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;

  static bool _hasUtf16LeBom(Uint8List bytes) =>
      bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE;

  static bool _hasUtf16BeBom(Uint8List bytes) =>
      bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF;
}

/// Legado 偵測編碼用的 ICU `CharsetDetector`（`lib/icu4j/`）裡夜讀解得了的
/// 五個辨識器：UTF-8、UTF-16BE、UTF-16LE、GB18030、Big5。每個算一個 0～100
/// 的信心，挑最高的；一樣高時挑排在後面的（ICU 照信心穩定排序再反過來）。
/// ICU 的其他辨識器（ISO-8859-x、KOI8-R、Shift_JIS、EUC、UTF-32）對應的編碼
/// 夜讀解不了，不搬，所以純英文這類 Legado 判成 ISO-8859-1 的，夜讀判
/// UTF-8，畫面上的字一樣。只看前 512KB（Legado 讀 TXT 時也只拿這麼多）。
class _IcuGuess {
  _IcuGuess(Uint8List bytes)
    : _input = bytes.length > 512000
          ? Uint8List.sublistView(bytes, 0, 512000)
          : bytes;

  final Uint8List _input;

  String best() {
    final candidates = <(String, int)>[
      ('UTF-8', _utf8()),
      ('UTF-16BE', _utf16(bigEndian: true)),
      ('UTF-16LE', _utf16(bigEndian: false)),
      // 同分時排在後面的贏。ICU 是 Big5 在後；夜讀讓 GBK 贏：10 個字以內的
      // 短文字兩邊都是 10 分、分不出來，照改用 ICU 之前的判斷當 GB18030（Legado
      // 在這種情況也常判錯）。
      ('Big5', _mbcs(_big5Next, _big5Common)),
      ('GB18030', _mbcs(_gb18030Next, _gb18030Common)),
    ];
    var best = 'UTF-8';
    var confidence = 0;
    for (final (name, value) in candidates) {
      if (value > 0 && value >= confidence) {
        best = name;
        confidence = value;
      }
    }
    return best;
  }

  /// `CharsetRecog_UTF8.match`。
  int _utf8() {
    var valid = 0;
    var invalid = 0;
    for (var i = 0; i < _input.length; i++) {
      var b = _input[i];
      if (b & 0x80 == 0) continue;
      int trail;
      if (b & 0xE0 == 0xC0) {
        trail = 1;
      } else if (b & 0xF0 == 0xE0) {
        trail = 2;
      } else if (b & 0xF8 == 0xF0) {
        trail = 3;
      } else {
        invalid++;
        continue;
      }
      while (true) {
        i++;
        if (i >= _input.length) break;
        b = _input[i];
        if (b & 0xC0 != 0x80) {
          invalid++;
          break;
        }
        if (--trail == 0) {
          valid++;
          break;
        }
      }
    }
    if (valid > 3 && invalid == 0) return 100;
    if (valid > 0 && invalid == 0) return 80;
    if (valid == 0 && invalid == 0) return 15;
    if (valid > invalid * 10) return 25;
    return 0;
  }

  /// `CharsetRecog_UTF_16_BE`／`_LE.match`：只看前 30 個位元組。
  int _utf16({required bool bigEndian}) {
    var confidence = 10;
    final check = _input.length < 30 ? _input.length : 30;
    for (var i = 0; i < check - 1; i += 2) {
      final unit = bigEndian
          ? (_input[i] << 8) | _input[i + 1]
          : (_input[i + 1] << 8) | _input[i];
      if (i == 0 && unit == 0xFEFF) return 100;
      if (unit == 0) {
        confidence -= 10;
      } else if ((unit >= 0x20 && unit <= 0xFF) || unit == 0x0A) {
        confidence += 10;
      }
      confidence = confidence.clamp(0, 100);
      if (confidence == 0 || confidence == 100) break;
    }
    if (check < 4 && confidence < 100) return 0;
    return confidence;
  }

  /// `CharsetRecog_mbcs.match`：數雙位元組字、壞字與常用字。
  int _mbcs(_NextChar next, List<int> common) {
    var doubleByte = 0;
    var commonCount = 0;
    var bad = 0;
    var total = 0;
    final iter = _Iter(_input);
    while (next(iter)) {
      total++;
      if (iter.error) {
        bad++;
      } else if (iter.value > 0xFF) {
        doubleByte++;
        if (_binarySearch(common, iter.value)) commonCount++;
      }
      if (bad >= 2 && bad * 5 >= doubleByte) return 0;
    }
    if (doubleByte <= 10 && bad == 0) {
      return doubleByte == 0 && total < 10 ? 0 : 10;
    }
    if (doubleByte < 20 * bad) return 0;
    final scale = 90.0 / math.log(doubleByte / 4);
    final confidence = (math.log(commonCount + 1) * scale + 10).toInt();
    return confidence > 100 ? 100 : confidence;
  }

  static bool _binarySearch(List<int> sorted, int value) {
    var low = 0;
    var high = sorted.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final v = sorted[mid];
      if (v == value) return true;
      if (v < value) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return false;
  }

  /// `CharsetRecog_big5.nextChar`。
  static bool _big5Next(_Iter it) {
    it.error = false;
    final first = it.nextByte();
    if (first < 0) return false;
    it.value = first;
    if (first <= 0x7F || first == 0xFF) return true;
    final second = it.nextByte();
    if (second < 0) return false;
    it.value = (first << 8) | second;
    if (second < 0x40 || second == 0x7F || second == 0xFF) it.error = true;
    return true;
  }

  /// `CharsetRecog_gb_18030.nextChar`（`second >= 80` 是 ICU 原本的寫法，
  /// 十進位，照抄）。
  static bool _gb18030Next(_Iter it) {
    it.error = false;
    final first = it.nextByte();
    if (first < 0) return false;
    it.value = first;
    if (first <= 0x80) return true;
    final second = it.nextByte();
    it.value = (first << 8) | second;
    if (first >= 0x81 && first <= 0xFE) {
      if ((second >= 0x40 && second <= 0x7E) ||
          (second >= 80 && second <= 0xFE)) {
        return true;
      }
      if (second >= 0x30 && second <= 0x39) {
        final third = it.nextByte();
        if (third >= 0x81 && third <= 0xFE) {
          final fourth = it.nextByte();
          if (fourth >= 0x30 && fourth <= 0x39) {
            it.value = (it.value << 16) | (third << 8) | fourth;
            return true;
          }
        }
      }
      it.error = true;
    }
    return !it.done;
  }

  static const List<int> _big5Common = [
    0xa140,
    0xa141,
    0xa142,
    0xa143,
    0xa147,
    0xa149,
    0xa175,
    0xa176,
    0xa440,
    0xa446, //
    0xa447,
    0xa448,
    0xa451,
    0xa454,
    0xa457,
    0xa464,
    0xa46a,
    0xa46c,
    0xa477,
    0xa4a3,
    0xa4a4,
    0xa4a7,
    0xa4c1,
    0xa4ce,
    0xa4d1,
    0xa4df,
    0xa4e8,
    0xa4fd,
    0xa540,
    0xa548,
    0xa558,
    0xa569,
    0xa5cd,
    0xa5e7,
    0xa657,
    0xa661,
    0xa662,
    0xa668,
    0xa670,
    0xa6a8,
    0xa6b3,
    0xa6b9,
    0xa6d3,
    0xa6db,
    0xa6e6,
    0xa6f2,
    0xa740,
    0xa751,
    0xa759,
    0xa7da,
    0xa8a3,
    0xa8a5,
    0xa8ad,
    0xa8d1,
    0xa8d3,
    0xa8e4,
    0xa8fc,
    0xa9c0,
    0xa9d2,
    0xa9f3,
    0xaa6b,
    0xaaba,
    0xaabe,
    0xaacc,
    0xaafc,
    0xac47,
    0xac4f,
    0xacb0,
    0xacd2,
    0xad59,
    0xaec9,
    0xafe0,
    0xb0ea,
    0xb16f,
    0xb2b3,
    0xb2c4,
    0xb36f,
    0xb44c,
    0xb44e,
    0xb54c,
    0xb5a5,
    0xb5bd,
    0xb5d0,
    0xb5d8,
    0xb671,
    0xb7ed,
    0xb867,
    0xb944,
    0xbad8,
    0xbb44,
    0xbba1, 0xbdd1, 0xc2c4, 0xc3b9, 0xc440, 0xc45f,
  ];

  static const List<int> _gb18030Common = [
    0xa1a1,
    0xa1a2,
    0xa1a3,
    0xa1a4,
    0xa1b0,
    0xa1b1,
    0xa1f1,
    0xa1f3,
    0xa3a1,
    0xa3ac, //
    0xa3ba,
    0xb1a8,
    0xb1b8,
    0xb1be,
    0xb2bb,
    0xb3c9,
    0xb3f6,
    0xb4f3,
    0xb5bd,
    0xb5c4,
    0xb5e3,
    0xb6af,
    0xb6d4,
    0xb6e0,
    0xb7a2,
    0xb7a8,
    0xb7bd,
    0xb7d6,
    0xb7dd,
    0xb8b4,
    0xb8df,
    0xb8f6,
    0xb9ab,
    0xb9c9,
    0xb9d8,
    0xb9fa,
    0xb9fd,
    0xbacd,
    0xbba7,
    0xbbd6,
    0xbbe1,
    0xbbfa,
    0xbcbc,
    0xbcdb,
    0xbcfe,
    0xbdcc,
    0xbecd,
    0xbedd,
    0xbfb4,
    0xbfc6,
    0xbfc9,
    0xc0b4,
    0xc0ed,
    0xc1cb,
    0xc2db,
    0xc3c7,
    0xc4dc,
    0xc4ea,
    0xc5cc,
    0xc6f7,
    0xc7f8,
    0xc8ab,
    0xc8cb,
    0xc8d5,
    0xc8e7,
    0xc9cf,
    0xc9fa,
    0xcab1,
    0xcab5,
    0xcac7,
    0xcad0,
    0xcad6,
    0xcaf5,
    0xcafd,
    0xccec,
    0xcdf8,
    0xceaa,
    0xcec4,
    0xced2,
    0xcee5,
    0xcfb5,
    0xcfc2,
    0xcfd6,
    0xd0c2,
    0xd0c5,
    0xd0d0,
    0xd0d4,
    0xd1a7,
    0xd2aa,
    0xd2b2,
    0xd2b5,
    0xd2bb,
    0xd2d4,
    0xd3c3,
    0xd3d0,
    0xd3fd,
    0xd4c2,
    0xd4da,
    0xd5e2,
    0xd6d0,
  ];
}

typedef _NextChar = bool Function(_Iter it);

/// `CharsetRecog_mbcs.iteratedChar`。
class _Iter {
  _Iter(this._bytes);

  final Uint8List _bytes;
  int _next = 0;
  int value = 0;
  bool error = false;
  bool done = false;

  int nextByte() {
    if (_next >= _bytes.length) {
      done = true;
      return -1;
    }
    return _bytes[_next++];
  }
}
