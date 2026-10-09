package io.abner.flutter_js

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * The Dart side drives QuickJS over FFI (libfastdev_quickjs_runtime.so from the
 * fastdev-jsruntimes-quickjs dependency); this plugin only exists so Flutter
 * links that Android library into the app.
 */
class FlutterJsPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {}

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
