import 'semantic_paragraph_formatter.dart';

/// 「重新分段」：讀者替一本書打開後，把網站存錯的換行全部重排（ADR 0078）。
///
/// 照 Legado 的 `ContentHelp.reSegment` 移植：不以句末標點收尾的行接到下一
/// 行（跨過空白行），再照對白與句子數重新切段、修正引號方向。和 Legado 刻意
/// 不同的地方：
///
/// - 只有插圖的行是邊界，兩張插圖之間各自重排，圖不會被併進字裡。
/// - 重排前先跑一次 [SemanticParagraphFormatter] 的修復，行首落單的收引號
///   接回上一句，不會被當成新的對白。
/// - 段內空白照 Legado 刪掉，兩邊都是英數字的留一個；接起來的兩行兩邊都是
///   英數字時補一個空格。
/// - 長段要不要拆用這一段的字算出的固定亂數（[_SeededRandom]），同一章每次
///   與每台手機都一樣。
/// - 「」和 “” 一樣當引號；原文只用「」時，重排完換回「」。說話的字與列舉
///   的連接詞也認繁體。
abstract final class ContentReSegmenter {
  static String reSegment(String content, {required String chapterTitle}) {
    final lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final output = <String>[];
    final block = <String>[];
    var title = chapterTitle;
    void flush() {
      if (block.any((line) => line.trim().isNotEmpty)) {
        output.add(_reSegmentBlock(block.join('\n'), title));
        title = '';
      }
      block.clear();
    }

    for (final line in lines) {
      if (_isIllustrationOnly(line)) {
        flush();
        output.add(line.trim());
      } else {
        block.add(line);
      }
    }
    flush();
    return output.join('\n');
  }

  static bool _isIllustrationOnly(String line) {
    final trimmed = line.trim();
    if (!trimmed.codeUnits.any(_isPlaceholder)) return false;
    return String.fromCharCodes(
      trimmed.codeUnits.where((unit) => !_isPlaceholder(unit)),
    ).trim().isEmpty;
  }

  static bool _isPlaceholder(int unit) => unit >= 0xE000 && unit <= 0xF8FF;

  static String _reSegmentBlock(String source, String chapterTitle) {
    // 先做有證據的修復：行首落單的收引號這類，Legado 會把它當成新的一段
    // 對白、補成一整對引號。
    final content = SemanticParagraphFormatter.repair(source);
    final corner = content.contains('「') || content.contains('」');
    final curly = content.contains('“') || content.contains('”');
    final result = _legadoReSegment(
      content.replaceAll('「', '“').replaceAll('」', '”'),
      chapterTitle,
    );
    if (corner && !curly) {
      return result.replaceAll('“', '「').replaceAll('”', '」');
    }
    return result;
  }

  static String _legadoReSegment(String content, String chapterName) {
    final dict = _makeDict(content);
    var p = content
        .replaceAll('&quot;', '“')
        .replaceAll(RegExp('[:：][\'"‘”“]+'), '：“')
        .replaceAll(RegExp('["”“]+\\s*["”“][\\s"”“]*'), '”\n“')
        .split(RegExp(r'\n(\s*)'));

    // 章節格式是章名、空行、首段，所以首行和章名一樣時略過。
    final buffer = <int>[0x20, 0x20];
    if (chapterName.trim() != p[0].trim()) {
      buffer.addAll(_removeSpaces(p[0]).codeUnits);
    }
    // 原文分段錯了，先把段落接回去。
    for (var i = 1; i < p.length; i++) {
      final last = buffer.last;
      final line = _removeSpaces(p[i]);
      if (_match(_sentencesEnd, last) ||
          (_match(_quotationRight, last) &&
              _match(_sentencesEnd, buffer[buffer.length - 2]))) {
        buffer.add(0x0A);
      } else if (line.isNotEmpty &&
          _isLatinLetterOrDigit(last) &&
          _isLatinLetterOrDigit(line.codeUnitAt(0))) {
        buffer.add(0x20);
      }
      buffer.addAll(line.codeUnits);
    }

    // 預分段：”“ 切成 ”\n“；”。“ 切成 ”。\n“；”。xxx 切成 ”。\nxxx。
    p = String.fromCharCodes(buffer)
        .replaceAll(RegExp('["”“]+\\s*["”“]+'), '”\n“')
        .replaceAllMapped(
          RegExp('["”“]+(？。！?!~)["”“]+'),
          (m) => '”${m[1]}\n“',
        )
        .replaceAllMapped(
          RegExp('["”“]+(？。！?!~)([^"”“])'),
          (m) => '”${m[1]}\n${m[2]}',
        )
        .replaceAllMapped(
          RegExp('([$_sentencesSay])[.。]'),
          (m) => '${m[1]}。\n',
        )
        .split('\n');
    final lines = StringBuffer();
    for (final s in p) {
      lines
        ..write('\n')
        ..write(_findNewLines(s, dict));
    }
    return _reduceLength(lines.toString())
        .replaceFirst(RegExp(r'^\s+'), '')
        .replaceAll(RegExp('\\s*["”“]+\\s*["”“][\\s"”“]*'), '”\n“')
        .replaceAll(RegExp('[:：][”“"\\s]+'), '：“')
        .replaceAllMapped(
          RegExp('\n["“”]([^\n"“”]+)([,:，：]["”“])([^\n"“”]+)'),
          (m) => '\n${m[1]}：“${m[3]}',
        )
        .replaceAll(RegExp(r'\n(\s*)'), '\n');
  }

  /// Legado 刪掉段內所有空白；夜讀留下兩邊都是英數字的空白（連續的縮成
  /// 一個），英文單字才不會黏在一起。
  static String _removeSpaces(String line) {
    final units = line.codeUnits;
    final output = <int>[];
    var i = 0;
    while (i < units.length) {
      if (!_isSpace(units[i])) {
        output.add(units[i]);
        i++;
        continue;
      }
      var end = i;
      while (end < units.length && _isSpace(units[end])) {
        end++;
      }
      if (output.isNotEmpty &&
          end < units.length &&
          _isLatinLetterOrDigit(output.last) &&
          _isLatinLetterOrDigit(units[end])) {
        output.add(0x20);
      }
      i = end;
    }
    return String.fromCharCodes(output);
  }

  static bool _isSpace(int unit) =>
      unit == 0x3000 ||
      unit == 0x20 ||
      unit == 0x09 ||
      unit == 0x0A ||
      unit == 0x0B ||
      unit == 0x0C ||
      unit == 0x0D ||
      unit == 0xA0;

  static bool _isLatinLetterOrDigit(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A);

  /// 強制切分，減少段落內的句子：連續兩段是沒有提示語的引號時進入對話
  /// 模式，最後一對引號後強制切段。
  static String _reduceLength(String str) {
    final p = str.split('\n');
    final l = p.length;
    final b = [for (final line in p) _paragraphDialog.hasMatch(line)];
    var dialogue = 0;
    for (var i = 0; i < l; i++) {
      if (b[i]) {
        if (dialogue < 0) {
          dialogue = 1;
        } else if (dialogue < 2) {
          dialogue++;
        }
      } else {
        if (dialogue > 1) {
          p[i] = _splitQuote(p[i]);
          dialogue--;
        } else if (dialogue > 0 && i < l - 2) {
          if (b[i + 1]) p[i] = _splitQuote(p[i]);
        }
      }
    }
    final string = StringBuffer();
    for (var i = 0; i < l; i++) {
      string
        ..write('\n')
        ..write(p[i]);
    }
    return string.toString();
  }

  /// 強制切分進入對話模式後，沒有構成 “xxx” 形式的段落。
  static String _splitQuote(String str) {
    final length = str.length;
    if (length < 3) return str;
    if (_match(_quotation, str.codeUnitAt(0))) {
      final i = _seekIndex(str, _quotation, 1, length - 2, true) + 1;
      if (i > 1 && !_match(_quotationBefore, str.codeUnitAt(i - 1))) {
        return '${str.substring(0, i)}\n${str.substring(i)}';
      }
    } else if (_match(_quotation, str.codeUnitAt(length - 1))) {
      final i = length - 1 - _seekIndex(str, _quotation, 1, length - 2, false);
      if (i > 1 && !_match(_quotationBefore, str.codeUnitAt(i - 1))) {
        return '${str.substring(0, i)}\n${str.substring(i)}';
      }
    }
    return str;
  }

  /// 算出在句末插入換行的位置。Legado 用亂數決定每個句末要不要切；這裡
  /// 用 [str] 算出的固定亂數，機率一樣。
  ///
  /// [offset] 加到結果上；[min] 最少幾句才切；[gain] 越大越不容易切。
  static List<int> _forceSplit(
    String str,
    int offset,
    int min,
    int gain,
    int trigger,
  ) {
    final result = <int>[];
    final arrayEnd = _seekIndexes(str, _sentencesEndP, 0, str.length - 2);
    final arrayMid = _seekIndexes(str, _sentencesMid, 0, str.length - 2);
    if (arrayEnd.length < trigger && arrayMid.length < trigger * 3) {
      return result;
    }
    final random = _SeededRandom(str);
    var j = 0;
    var i = min;
    while (i < arrayEnd.length) {
      var k = 0;
      while (j < arrayMid.length) {
        if (arrayMid[j] < arrayEnd[i]) k++;
        j++;
      }
      if (random.nextDouble() * gain < 0.8 + k / 2.5) {
        result.add(arrayEnd[i] + offset);
        i = i + min > i ? i + min : i;
      }
      i++;
    }
    return result;
  }

  /// 對已經用換行預先切開的一段重新劃分段落。
  static String _findNewLines(String str, List<String> dict) {
    final string = str.codeUnits.toList();
    // 每個引號的位置。用引號列舉時（“鍋”、“碗”）當成只有一對引號。
    final arrayQuote = <int>[];
    // 要插入換行的位置（[str] 的下標）。
    var insN = <int>[];
    // 每個引號之後的字在引號內（正）還是引號外（負），0 是未知。
    final mod = List<int>.filled(str.length + 1, 0);
    var waitClose = false;
    for (var i = 0; i < str.length; i++) {
      final c = str.codeUnitAt(i);
      if (!_match(_quotation, c)) continue;
      final size = arrayQuote.length;
      // 把 “xxx”、“yy” 併成 “xxx_yy” 處理。
      if (size > 0) {
        final quotePre = arrayQuote[size - 1];
        if (i - quotePre == 2) {
          var remove = false;
          if (waitClose) {
            if (_match(',，、/', str.codeUnitAt(i - 1))) remove = true;
          } else if (_match(_enumerationJoiners, str.codeUnitAt(i - 1))) {
            remove = true;
          }
          if (remove) {
            string[i] = 0x201C; // “
            string[i - 2] = 0x201D; // ”
            arrayQuote.removeAt(size - 1);
            mod[size - 1] = 1;
            mod[size] = -1;
            continue;
          }
        }
      }
      arrayQuote.add(i);

      // 為 xxx：“xxx” 做標記。
      if (i > 1) {
        // 這次發言開引號的前一個字。
        final charB1 = str.codeUnitAt(i - 1);
        // 上次發言開引號的前一個字。
        var charB2 = 0;
        if (_match(_quotationBefore, charB1)) {
          // 不是第一處引號時，找上一處斷句分段。
          if (arrayQuote.length > 1) {
            final lastQuote = arrayQuote[arrayQuote.length - 2];
            var p = 0;
            if (charB1 == 0x2C || charB1 == 0xFF0C) {
              if (arrayQuote.length > 2) {
                p = arrayQuote[arrayQuote.length - 3];
                if (p > 0) charB2 = str.codeUnitAt(p - 1);
              }
            }
            if (_match(_sentencesEndP, charB2)) {
              insN.add(p - 1);
            } else if (!_match('的', charB2)) {
              final lastEnd = _seekLast(str, _sentencesEnd, i, lastQuote);
              insN.add(lastEnd > 0 ? lastEnd : lastQuote);
            }
          }
          waitClose = true;
          mod[size] = 1;
          if (size > 0) {
            mod[size - 1] = -1;
            if (size > 1) mod[size - 2] = 1;
          }
        } else if (waitClose) {
          waitClose = false;
          insN.add(i);
        }
      }
    }
    final size = arrayQuote.length;

    // 這個位置之前的引號是否已經配對。
    var opened = false;
    if (size > 0) {
      // 第一輪：讓每個 mod 都不是 0。
      for (var i = 0; i < size; i++) {
        if (mod[i] > 0) {
          opened = true;
        } else if (mod[i] < 0) {
          // 連續兩個收引號表示衝突，前一個強制當開引號。
          if (!opened && i > 0) mod[i] = 3;
          opened = false;
        } else {
          opened = !opened;
          mod[i] = opened ? 2 : -2;
        }
      }
      // 段尾必須收引號。
      if (opened) {
        if (arrayQuote[size - 1] - string.length > -3) {
          if (size > 1) mod[size - 2] = 4;
          mod[size - 1] = -4;
        } else if (!_match(_sentencesSay, string[string.length - 2])) {
          string.add(0x201D); // ”
        }
      }

      // 第二輪：mod 由負轉正時，前一個字是句末就插入換行。
      var loop2Mod1 = -1;
      var i = 0;
      if (arrayQuote[0] - 1 < 0) {
        i = 1;
        loop2Mod1 = 0;
      }
      while (i < size) {
        final j = arrayQuote[i] - 1;
        final loop2Mod2 = mod[i];
        if (loop2Mod1 < 0 &&
            loop2Mod2 > 0 &&
            _match(_sentencesEnd, string[j])) {
          insN.add(j);
        }
        loop2Mod1 = loop2Mod2;
        i++;
      }
    }

    // 用字典檢查換行位置：引號裡是字典詞條，或是 xx的“xx” 時，後面不換行。
    final insN1 = <int>[];
    for (final i in insN) {
      if (_match('"\'”“', string[i])) {
        final start = _seekLast(str, '"\'”“', i - 1, i - _wordMaxLength);
        if (start > 0) {
          final word = str.substring(start + 1, i);
          if (dict.contains(word)) continue;
          if (_match('的地得', str.codeUnitAt(start))) continue;
        }
      }
      insN1.add(i);
    }
    insN = insN1.toSet().toList()..sort();

    // 在句末插入換行（Legado 用亂數，見 [_forceSplit]）。
    {
      var j = 0;
      var progress = 0;
      var nextLine = -1;
      if (insN.isNotEmpty) nextLine = insN[j];
      var gain = 3;
      var min = 0;
      var trigger = 2;
      for (final quote in arrayQuote) {
        if (quote > 0) {
          gain = 4;
          min = 2;
          trigger = 4;
        } else {
          gain = 3;
          min = 0;
          trigger = 2;
        }
        // 把引號前的換行與內容相間插入。
        while (j < insN.length) {
          if (nextLine >= quote) break;
          nextLine = insN[j];
          if (progress < nextLine) {
            final subs = String.fromCharCodes(string, progress, nextLine);
            insN.addAll(_forceSplit(subs, progress, min, gain, trigger));
            progress = nextLine + 1;
          }
          j++;
        }
        if (progress < quote) {
          final subs = String.fromCharCodes(string, progress, quote + 1);
          insN.addAll(_forceSplit(subs, progress, min, gain, trigger));
          progress = quote + 1;
        }
      }
      while (j < insN.length) {
        nextLine = insN[j];
        if (progress < nextLine) {
          final subs = String.fromCharCodes(string, progress, nextLine);
          insN.addAll(_forceSplit(subs, progress, min, gain, trigger));
          progress = nextLine + 1;
        }
        j++;
      }
      if (progress < string.length) {
        final subs = String.fromCharCodes(string, progress);
        insN.addAll(_forceSplit(subs, progress, min, gain, trigger));
      }
    }

    // 照段落狀態修正引號方向；insQuote[i] 表示 arrayQuote[i] 的引號前要補
    // 一個收引號。
    final insQuote = List<bool>.filled(size, false);
    opened = false;
    for (var i = 0; i < size; i++) {
      final p = arrayQuote[i];
      if (mod[i] > 0) {
        string[p] = 0x201C;
        if (opened) insQuote[i] = true;
        opened = true;
      } else if (mod[i] < 0) {
        string[p] = 0x201D;
        opened = false;
      } else {
        opened = !opened;
        string[p] = opened ? 0x201C : 0x201D;
      }
    }
    insN = insN.toSet().toList()..sort();

    // 從 string 複製，插入引號與換行。
    final buffer = <int>[];
    void append(int start, int end) {
      final from = start < 0 ? 0 : start;
      final to = end > string.length ? string.length : end;
      if (from < to) buffer.addAll(string.getRange(from, to));
    }

    var j = 0;
    var progress = 0;
    var nextLine = -1;
    if (insN.isNotEmpty) nextLine = insN[j];
    for (var i = 0; i < arrayQuote.length; i++) {
      final quote = arrayQuote[i];
      while (j < insN.length) {
        if (nextLine >= quote) break;
        nextLine = insN[j];
        append(progress, nextLine + 1);
        buffer.add(0x0A);
        progress = nextLine + 1;
        j++;
      }
      if (progress < quote) {
        append(progress, quote + 1);
        progress = quote + 1;
      }
      if (insQuote[i] && buffer.length > 2) {
        if (buffer.last == 0x0A) {
          buffer.add(0x201C);
        } else {
          buffer.insertAll(buffer.length - 1, const [0x201D, 0x0A]);
        }
      }
    }
    while (j < insN.length) {
      nextLine = insN[j];
      if (progress <= nextLine) {
        append(progress, nextLine + 1);
        buffer.add(0x0A);
        progress = nextLine + 1;
      }
      j++;
    }
    if (progress < string.length) append(progress, string.length);
    return String.fromCharCodes(buffer);
  }

  /// 引號圍住、出現不只一次的詞（引號中間沒有標點），列舉用的字典。
  static List<String> _makeDict(String str) {
    final cache = <String>{};
    final dict = <String>[];
    for (final match in _dictPattern.allMatches(str)) {
      final word = match[0]!;
      if (!cache.add(word) && !dict.contains(word)) dict.add(word);
    }
    return dict;
  }

  /// [str] 裡符合 [key] 的每個字的位置（連續的只記最後一個）。
  static List<int> _seekIndexes(String str, String key, int from, int to) {
    final list = <int>[];
    if (str.length - from < 1) return list;
    var i = from > 0 ? from : 0;
    var t = str.length;
    if (to > 0 && to < t) t = to;
    while (i < t) {
      if (_match(key, str.codeUnitAt(i))) {
        if (list.isNotEmpty && i - list.last == 1) {
          list[list.length - 1] = i;
        } else {
          list.add(i);
        }
      }
      i++;
    }
    return list;
  }

  /// 從 [from] 往前找到 [to]（不含）為止，最後一個符合 [key] 的位置。
  static int _seekLast(String str, String key, int from, int to) {
    if (str.length - from < 1) return -1;
    var i = str.length - 1;
    if (from < i && i > 0) i = from;
    final t = to > 0 ? to : 0;
    while (i > t) {
      if (_match(key, str.codeUnitAt(i))) return i;
      i--;
    }
    return -1;
  }

  /// 到最近一個符合 [key] 的字的距離（不是下標）；[inOrder] 為 false 時從
  /// 尾端往前算。
  static int _seekIndex(String str, String key, int from, int to, bool inOrder) {
    if (str.length - from < 1) return -1;
    var i = from > 0 ? from : 0;
    var t = str.length;
    if (to > 0 && to < t) t = to;
    while (i < t) {
      final c = inOrder
          ? str.codeUnitAt(i)
          : str.codeUnitAt(str.length - i - 1);
      if (_match(key, c)) return i;
      i++;
    }
    return -1;
  }

  static bool _match(String rule, int unit) =>
      rule.codeUnits.contains(unit);

  /// 句末標點；引號可能判斷錯，不含引號。
  static const String _sentencesEnd = '？。！?!~';
  static const String _sentencesEndP = '.？。！?!~';

  /// 句中標點；有些網站常把「，」寫成「.」，英文句點當句中標點。
  static const String _sentencesMid = '.，、,—…';

  /// 說話的字，Legado 只有簡體，這裡補上繁體。
  static const String _sentencesSay = '问说喊唱叫骂道着答問說罵著';

  /// 列舉時夾在兩組引號中間的字（“鍋”和“碗”）。
  static const String _enumerationJoiners = ',，、/和与或與';

  /// xxx說：“” 的冒號。
  static const String _quotationBefore = '，：,:';
  static const String _quotation = '"“”';
  static const String _quotationRight = '"”';
  static final RegExp _paragraphDialog = RegExp('^["”“][^"”“]+["”“]\$');

  /// 字典詞條最長幾個字。
  static const int _wordMaxLength = 16;
  static final RegExp _dictPattern = RegExp(
    '(?<=["\'”“])([^\n\\p{P}]{1,$_wordMaxLength})(?=["\'”“])',
    unicode: true,
  );
}

/// 用一段字算出的固定亂數：FNV-1a 雜湊當種子、xorshift32 往下產生，不用
/// `String.hashCode`（不保證各版本、各平台一樣）。
final class _SeededRandom {
  _SeededRandom(String text) {
    var hash = 0x811C9DC5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    _state = hash == 0 ? 0x9E3779B9 : hash;
  }

  late int _state;

  double nextDouble() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x & 0xFFFFFFFF;
    return _state / 4294967296.0;
  }
}
