import 'package:punycoder/punycoder.dart';
import 'package:unorm_dart/unorm_dart.dart';

import 'idna_mapping_table.dart';

/// UTS #46 對應表裡一個碼位的狀態（順序同 tool/idna_mapping.dart）。
enum IdnaStatus { valid, ignored, mapped, deviation, disallowed }

/// 網域換成 ASCII（punycode），照 UTS #46 的非過渡處理，同 Legado 用的
/// OkHttp 與瀏覽器：逐字照對應表（全形轉半形、大寫轉小寫、該忽略的拿掉、
/// ß 這類保留），NFC，一段段不是 ASCII 的編成 `xn--…`；最後照 OkHttp 檢查
/// 主機名不能有的字元與每段長度。不合法時是 null。
String? idnaToAscii(String host) {
  final mapped = StringBuffer();
  for (final rune in host.runes) {
    final i = _rangeOf(rune);
    switch (IdnaStatus.values[idnaRangeKinds[i]]) {
      case IdnaStatus.valid:
      case IdnaStatus.deviation:
        mapped.writeCharCode(rune);
      case IdnaStatus.ignored:
        break;
      case IdnaStatus.mapped:
        mapped.write(idnaRangeMappings[i]);
      case IdnaStatus.disallowed:
        return null;
    }
  }
  final labels = nfc(mapped.toString()).split('.');
  final ascii = <String>[];
  for (final label in labels) {
    final isAscii = !label.runes.any((c) => c > 0x7f);
    ascii.add(isAscii ? label : 'xn--${punycode.encode(label)}');
  }
  final result = ascii.join('.');
  return _isValidAsciiHost(result, ascii) ? result : null;
}

/// 碼位所在的那一段：起點不大於它的最後一段。
int _rangeOf(int rune) {
  var lo = 0;
  var hi = idnaRangeStarts.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (idnaRangeStarts[mid] <= rune) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

/// OkHttp `toCanonicalHost`：不能有控制字元、非 ASCII 與 ` #%/:?@[\]`；每段
/// 1～63 字、整個最多 253 字（結尾的點不算一段）。
bool _isValidAsciiHost(String host, List<String> labels) {
  for (final c in host.codeUnits) {
    if (c <= 0x1f || c >= 0x7f) return false;
    if (' #%/:?@[\\]'.codeUnits.contains(c)) return false;
  }
  if (host.isEmpty || host.length > 253) return false;
  final parts = host.endsWith('.')
      ? labels.sublist(0, labels.length - 1)
      : labels;
  return parts.every((l) => l.isNotEmpty && l.length <= 63);
}
