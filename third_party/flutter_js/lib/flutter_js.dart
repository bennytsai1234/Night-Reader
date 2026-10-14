import 'dart:io';

import 'package:flutter_js/javascript_runtime.dart';
import 'package:flutter_js/javascriptcore/jscore_runtime.dart';

import './extensions/fetch.dart';
import './extensions/handle_promises.dart';
import './quickjs/quickjs_runtime2.dart';

export './extensions/handle_promises.dart';
export './quickjs/quickjs_runtime2.dart';
export 'javascript_runtime.dart';
export 'js_eval_result.dart';

/// 建立 JS 執行環境：iOS 用系統內建的 JavaScriptCore，其他平台用 QuickJS
/// （Android 為 App 本身；桌面上的 QuickJS 只供測試使用）。
JavascriptRuntime getJavascriptRuntime({bool xhr = true}) {
  final JavascriptRuntime runtime =
      Platform.isIOS ? JavascriptCoreRuntime() : QuickJsRuntime2();
  if (xhr) runtime.enableFetch();
  runtime.enableHandlePromises();
  return runtime;
}
