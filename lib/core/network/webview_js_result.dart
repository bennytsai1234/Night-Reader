import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 網頁跑 JS 傳回的結果轉成字串。Android 的 WebView 把字串包成 JSON 字串
/// （加引號與跳脫），解開才是 JS 傳回的那個字串；iOS 照原值給，不再解：
/// 規則 JS 傳回的 JSON 字串（`JSON.stringify('甲')`）才不會被多解一層。
/// HTML 實體不在這裡解，留給規則解析（同 Legado `unescapeJson`）。
String webViewJsResult(Object result) {
  final text = result.toString();
  if (defaultTargetPlatform == TargetPlatform.android &&
      text.length >= 2 &&
      text.startsWith('"') &&
      text.endsWith('"')) {
    return jsonDecode(text) as String;
  }
  return text;
}
