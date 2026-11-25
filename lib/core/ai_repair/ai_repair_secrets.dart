import 'dart:async';
import 'dart:convert';

import '../models/source/base_source.dart';
import '../models/source/book_source.dart';
import '../network/cookie_store.dart';
import '../network/network_service.dart';
import '../network/secret_text.dart';
import '../network/source_proxy.dart';
import '../diagnostics/app_log_service.dart';

/// 送給 AI 的內容裡換掉秘密的那段字。
const String aiRepairRedacted = hiddenSecret;

/// 太短的值不遮：「1」「true」這類會把整份內容遮得看不懂，也不是秘密。
const int _minSecretLength = 6;

/// 這個書源的秘密（ADR 0054：登入資料、Cookie 與書源變數不送）：登入表單
/// 填的內容、登入標頭、夜讀存的網站 Cookie（書源的與網路層 Cookie 罐裡這個
/// 網站的）、書源變數，與書源標頭裡的
/// Cookie、Authorization 與代理（帳號密碼）。它們抓網頁時照常帶上，值會出現
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
  // 網站回的 Cookie 存在網路層的 Cookie 罐，抓網頁時照網址帶上（同一個網站
  // 別的書源存的也算），值可能被網頁原樣印出來。
  await read('網站的 Cookie 罐', () async {
    final uri = Uri.tryParse(source.getKey());
    if (uri == null || !uri.hasScheme) return;
    final saved = await NetworkService().cookieJar.loadForRequest(uri);
    addAll([for (final cookie in saved) cookie.value]);
  });
  await read('書源變數', () async {
    final variable = await source.getVariable();
    addAll([variable, ..._jsonValues(variable)]);
  });
  return secrets;
}

/// [text] 裡出現的每個秘密換成 [aiRepairRedacted]（[hideSecrets]）。
String redactAiRepairSecrets(String text, Set<String> secrets) =>
    hideSecrets(text, secrets);

/// [text] 從 [start] 到 [end] 的那一段，遮掉 [secrets] 給 AI 看（讀頁、讀
/// 章節分段）。切點落在一段秘密中間時往外延到整段，前後兩段都只看得到遮過
/// 的；位置照原文算，秘密清單在兩次讀之間變了，接著讀也不缺字、不重複。
({String text, int start, int end}) aiRepairSlice(
  String text,
  int start,
  int end,
  Set<String> secrets,
) {
  final forms = {for (final secret in secrets) ...secretForms(secret)};
  int widen(int at, {required bool toEnd}) {
    for (var moved = true; moved;) {
      moved = false;
      for (final form in forms) {
        final from = (at - form.length + 1).clamp(0, text.length);
        final found = text.indexOf(form, from);
        if (found < 0 || found >= at || found + form.length <= at) continue;
        at = toEnd ? found + form.length : found;
        moved = true;
      }
    }
    return at;
  }

  final from = widen(start, toEnd: false);
  final to = widen(end, toEnd: true);
  return (
    text: redactAiRepairSecrets(text.substring(from, to), secrets),
    start: from,
    end: to,
  );
}

/// 這次修復現在要遮的秘密，給在背景 worker 裡截短的地方（試抓、看網頁、
/// 試解析、跑程式）帶過去先遮再截；不在 [withAiRepairSecrets] 裡時是空的。
Set<String> get currentAiRepairSecrets =>
    Zone.current[_secretsZoneKey] as Set<String>? ?? const {};

/// 在 [body] 裡 [currentAiRepairSecrets] 是 [secrets]。
Future<T> withAiRepairSecrets<T>(
  Set<String> secrets,
  Future<T> Function() body,
) => runZoned(body, zoneValues: {_secretsZoneKey: secrets});

final Object _secretsZoneKey = Object();

/// 這個書源在記憶體裡現在的 Cookie 值：修復途中規則或網站驗證才寫進來的
/// （[aiRepairSecretsOf] 只在開始時讀一次）。同步讀，每次遮蔽前都看。
Set<String> aiRepairLiveCookieSecrets(Iterable<String> urls) => {
  for (final url in urls)
    for (final value in _cookieValues(CookieStore().getMemoryCookie(url) ?? ''))
      if (value.trim().length >= _minSecretLength) value.trim(),
};

/// 書源標頭（JSON 物件）裡的 Cookie、Authorization 與代理：整段、Cookie 的
/// 每個值與代理的帳號密碼。
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
    } else if (name == 'proxy' && value != null) {
      yield* SourceProxy.secretsOf('$value');
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
