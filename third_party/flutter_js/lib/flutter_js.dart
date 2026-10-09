import 'package:flutter_js/javascript_runtime.dart';

import './extensions/fetch.dart';
import './extensions/handle_promises.dart';
import './quickjs/quickjs_runtime2.dart';

export './extensions/handle_promises.dart';
export './quickjs/quickjs_runtime2.dart';
export 'javascript_runtime.dart';
export 'js_eval_result.dart';

/// 建立 QuickJS 執行環境。App 只在 Android 上跑；桌面上的 QuickJS 只供測試使用。
JavascriptRuntime getJavascriptRuntime({bool xhr = true}) {
  final runtime = QuickJsRuntime2();
  if (xhr) runtime.enableFetch();
  runtime.enableHandlePromises();
  return runtime;
}
