import 'dart:convert';

import '../models/base_source.dart';
import '../models/book_source.dart';
import '../services/cookie_store.dart';
import '../services/app_log_service.dart';

/// 送給 AI 的內容裡換掉秘密的那段字。
const String aiRepairRedacted = '«已遮蔽»';

/// 太短的值不遮：「1」「true」這類會把整份內容遮得看不懂，也不是秘密。
const int _minSecretLength = 6;

/// 這個書源的秘密（ADR 0054：登入資料、Cookie 與書源變數不送）：登入表單
/// 填的內容、登入標頭、夜讀存的網站 Cookie、書源變數，與書源標頭裡的
/// Cookie、Authorization。它們不在書源 JSON 裡，但抓網頁時照常帶上，值會出現
/// 在試抓的網址、除錯紀錄與錯誤訊息裡，送出前用 [redactAiRepairSecrets]
/// 換掉。讀不到的那一種略過：書源抓網頁時同樣讀不到。
Future<Set<String>> aiRepairSecretsOf(BookSource source) async {
  final secrets = <String>{};
  void addAll(Iterable<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.length >= _minSecretLength) secrets.add(trimmed);
    }
  }

  Future<void> read(String what, Future<void> Function() work) async {
    try {
      await work();
    } catch (error) {
      AppLog.e('AI 修書源讀不到書源的$what: $error', error: error);
    }
  }

  addAll(_sensitiveHeaderValues(source.header));
  await read('登入資料', () async {
    final info = await source.getLoginInfo();
    addAll([?info, ...?(await source.getLoginInfoMap())?.values]);
  });
  await read('登入標頭', () async {
    final raw = await source.getLoginHeader();
    addAll([?raw, ...BaseSource.decodeLoginHeader(raw).values]);
  });
  await read('Cookie', () async {
    addAll(_cookieValues(await CookieStore().getCookie(source.getKey())));
  });
  await read('書源變數', () async {
    final variable = await source.getVariable();
    addAll([variable, ..._jsonValues(variable)]);
  });
  return secrets;
}

/// [text] 裡出現的每個秘密換成 [aiRepairRedacted]；長的先換，一段秘密包著
/// 另一段時不會只換掉一半。
String redactAiRepairSecrets(String text, Set<String> secrets) {
  if (secrets.isEmpty) return text;
  final ordered = secrets.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  var out = text;
  for (final secret in ordered) {
    for (final form in _forms(secret)) {
      out = out.replaceAll(form, aiRepairRedacted);
    }
  }
  return out;
}

/// 秘密在送出的文字裡可能長的樣子：原樣、網址編碼，與放進 JSON 字串後跳脫
/// 一層、兩層的（書源標頭本身是 JSON 字串，放進書源 JSON 又跳脫一層）。
Set<String> _forms(String secret) {
  String escaped(String value) {
    final json = jsonEncode(value);
    return json.substring(1, json.length - 1);
  }

  final once = escaped(secret);
  return {secret, Uri.encodeQueryComponent(secret), once, escaped(once)};
}

/// 這個書源在記憶體裡現在的 Cookie 值：修復途中規則或網站驗證才寫進來的
/// （[aiRepairSecretsOf] 只在開始時讀一次）。同步讀，每次遮蔽前都看。
Set<String> aiRepairLiveCookieSecrets(Iterable<String> urls) => {
  for (final url in urls)
    for (final value in _cookieValues(CookieStore().getMemoryCookie(url) ?? ''))
      if (value.trim().length >= _minSecretLength) value.trim(),
};

/// 書源標頭（JSON 物件）裡的 Cookie 與 Authorization：整段與 Cookie 的每個值。
Iterable<String> _sensitiveHeaderValues(String? header) sync* {
  if (header == null || header.trim().isEmpty) return;
  final Object? decoded;
  try {
    decoded = jsonDecode(header);
  } on FormatException {
    return;
  }
  if (decoded is! Map) return;
  for (final MapEntry(:key, :value) in decoded.entries) {
    final name = '$key'.toLowerCase();
    if (name == 'cookie') {
      yield '$value';
      yield* _cookieValues('$value');
    } else if (name == 'authorization') {
      yield '$value';
      final parts = '$value'.split(' ');
      if (parts.length == 2) yield parts.last;
    }
  }
}

/// `a=1; b=2` 每個 Cookie 的值。
Iterable<String> _cookieValues(String cookie) sync* {
  for (final pair in cookie.split(';')) {
    final at = pair.indexOf('=');
    if (at > 0) yield pair.substring(at + 1);
  }
}

/// 變數是 JSON 物件時，裡面每個值。
Iterable<String> _jsonValues(String text) sync* {
  if (!text.trimLeft().startsWith('{')) return;
  try {
    if (jsonDecode(text) case final Map<dynamic, dynamic> map) {
      for (final value in map.values) {
        if (value is String || value is num) yield '$value';
      }
    }
  } on FormatException {
    return;
  }
}
