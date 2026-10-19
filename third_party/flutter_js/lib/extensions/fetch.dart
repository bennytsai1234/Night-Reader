import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/javascript_runtime.dart';
import './xhr.dart';

var _fetchDebug = false;

bool setFetchDebug(bool value) => _fetchDebug = value;

/// The fetch.js polyfill text, for isolates without `rootBundle`.
///
/// A background isolate has no `ServicesBinding`, so it cannot read assets.
/// The root isolate reads `packages/flutter_js/assets/js/fetch.js` and hands
/// the text over; when this is set, [JavascriptRuntimeFetchExtension.enableFetch]
/// evaluates it synchronously instead of loading the asset.
String? fetchPolyfillSource;

extension JavascriptRuntimeFetchExtension on JavascriptRuntime {
  Future<JavascriptRuntime> enableFetch() async {
    debug('Before enable xhr');
    enableXhr();
    debug('After enable xhr');
    final fetchPolyfill = fetchPolyfillSource ??
        await rootBundle.loadString('packages/flutter_js/assets/js/fetch.js');
    debug('Loaded fetchPolyfill');
    final evalFetchResult = evaluate(fetchPolyfill);
    debug('Eval Fetch Result: $evalFetchResult');
    return this;
  }
}

void debug(String message) {
  if (_fetchDebug) {
    debugPrint('JavascriptRuntimeFetchExtension: $message');
  }
}
