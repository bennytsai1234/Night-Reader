import 'dart:convert';

/// 文字裡換掉秘密的那段字。
const String hiddenSecret = '«已遮蔽»';

/// [text] 裡出現的每個秘密換成 [hiddenSecret]；長的先換，一段秘密包著另一段
/// 時不會只換掉一半。要截短的文字先遮再截：截在一段秘密中間時，留下的半段
/// 認不出來。
String hideSecrets(String text, Set<String> secrets) {
  if (secrets.isEmpty) return text;
  final ordered = secrets.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  var out = text;
  for (final secret in ordered) {
    for (final form in secretForms(secret)) {
      out = out.replaceAll(form, hiddenSecret);
    }
  }
  return out;
}

/// 秘密在文字裡可能長的樣子：原樣、網址編碼，與放進 JSON 字串後跳脫一層、
/// 兩層的（書源標頭本身是 JSON 字串，放進書源 JSON 又跳脫一層）。
Set<String> secretForms(String secret) {
  String escaped(String value) {
    final json = jsonEncode(value);
    return json.substring(1, json.length - 1);
  }

  final once = escaped(secret);
  return {secret, Uri.encodeQueryComponent(secret), once, escaped(once)};
}
