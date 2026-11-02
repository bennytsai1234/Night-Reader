import 'public_suffix_rules.dart';

/// [host] 在公共字尾表上的可註冊網域：公共字尾再往左一段，同 OkHttp
/// `PublicSuffixDatabase.getEffectiveTldPlusOne`。`www.abc.com.cn` →
/// `abc.com.cn`、`foo.github.io` → `foo.github.io`；[host] 本身就是公共字尾
/// （`com.cn`、`localhost`）時傳回 null。不判斷 IP 位址，呼叫的地方先擋。
///
/// 規則照公共字尾表的說明：例外規則（`!`）優先，其次是最長的規則（含萬用的
/// `*.`），都不符合時當作最後一段是公共字尾。
String? registrableDomain(String host) {
  var domain = host.toLowerCase();
  if (domain.contains('%')) {
    // Dart 的 Uri 把非 ASCII 的網域編成 %XX，表上是原字。
    try {
      domain = Uri.decodeComponent(domain);
    } on ArgumentError {
      return null;
    }
  }
  if (domain.endsWith('.')) domain = domain.substring(0, domain.length - 1);
  final labels = domain.split('.');
  if (labels.any((label) => label.isEmpty)) return null;

  for (var i = 0; i < labels.length; i++) {
    if (_isRule('!${labels.skip(i).join('.')}')) {
      // 例外規則本身就是可註冊網域。
      return labels.skip(i).join('.');
    }
  }
  var suffixLength = 1;
  for (var i = 0; i < labels.length; i++) {
    final suffix = labels.skip(i).join('.');
    final wildcard = i + 1 < labels.length
        ? '*.${labels.skip(i + 1).join('.')}'
        : null;
    if (_isRule(suffix) || (wildcard != null && _isRule(wildcard))) {
      suffixLength = labels.length - i;
      break;
    }
  }
  if (labels.length == suffixLength) return null;
  return labels.skip(labels.length - suffixLength - 1).join('.');
}

bool _isRule(String rule) {
  var low = 0;
  var high = publicSuffixRules.length - 1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    final order = publicSuffixRules[mid].compareTo(rule);
    if (order == 0) return true;
    if (order < 0) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return false;
}
