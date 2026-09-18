package com.inkpage.reader;

import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import io.flutter.Log;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Plugin registration for the Flutter integration-test engine.
 *
 * <p>The production activity uses audio_service's shared engine. Registering
 * that plugin on the test engine would create the shared engine again and
 * prevent Flutter's test VM-service flags from reaching the running isolate.
 * Keep this list aligned with GeneratedPluginRegistrant.java, except for
 * audio_service.
 */
@Keep
public final class TestPluginRegistrant {
  private static final String TAG = "TestPluginRegistrant";

  private TestPluginRegistrant() {}

  public static void registerWith(@NonNull FlutterEngine flutterEngine) {
    try {
      flutterEngine.getPlugins().add(new com.llfbandit.app_links.AppLinksPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin app_links", e);
    }
    try {
      flutterEngine.getPlugins().add(new com.ryanheise.audio_session.AudioSessionPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin audio_session", e);
    }
    try {
      flutterEngine.getPlugins().add(new com.mr.flutter.plugin.filepicker.FilePickerPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin file_picker", e);
    }
    try {
      flutterEngine.getPlugins().add(new io.abner.flutter_js.FlutterJsPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin flutter_js", e);
    }
    try {
      flutterEngine.getPlugins().add(
          new io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin flutter_plugin_android_lifecycle", e);
    }
    try {
      flutterEngine.getPlugins().add(new com.eyedeadevelopment.fluttertts.FlutterTtsPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin flutter_tts", e);
    }
    try {
      flutterEngine.getPlugins().add(new io.flutter.plugins.imagepicker.ImagePickerPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin image_picker_android", e);
    }
    registerIntegrationTestPluginIfPresent(flutterEngine);
    try {
      flutterEngine.getPlugins().add(new com.github.dart_lang.jni.JniPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin jni", e);
    }
    try {
      flutterEngine.getPlugins().add(new com.github.dart_lang.jni_flutter.JniFlutterPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin jni_flutter", e);
    }
    try {
      flutterEngine.getPlugins().add(new dev.fluttercommunity.plus.packageinfo.PackageInfoPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin package_info_plus", e);
    }
    try {
      flutterEngine.getPlugins().add(new com.baseflow.permissionhandler.PermissionHandlerPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin permission_handler_android", e);
    }
    try {
      flutterEngine.getPlugins().add(new com.kasem.receive_sharing_intent.ReceiveSharingIntentPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin receive_sharing_intent", e);
    }
    try {
      flutterEngine.getPlugins().add(new dev.fluttercommunity.plus.share.SharePlusPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin share_plus", e);
    }
    try {
      flutterEngine.getPlugins().add(new io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin shared_preferences_android", e);
    }
    try {
      flutterEngine.getPlugins().add(new com.tekartik.sqflite.SqflitePlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin sqflite_android", e);
    }
    try {
      flutterEngine.getPlugins().add(new io.flutter.plugins.urllauncher.UrlLauncherPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin url_launcher_android", e);
    }
    try {
      flutterEngine.getPlugins().add(new io.flutter.plugins.webviewflutter.WebViewFlutterPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin webview_flutter_android", e);
    }
    try {
      flutterEngine.getPlugins().add(new dev.fluttercommunity.workmanager.WorkmanagerPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin workmanager_android", e);
    }
  }

  /**
   * integration_test is available only to the test APK. Keep the production
   * release/debug compile classpath independent from that dev-only plugin.
   */
  private static void registerIntegrationTestPluginIfPresent(
      @NonNull FlutterEngine flutterEngine) {
    try {
      final Class<?> pluginClass =
          Class.forName("dev.flutter.plugins.integration_test.IntegrationTestPlugin");
      final Object plugin = pluginClass.getDeclaredConstructor().newInstance();
      if (!(plugin instanceof FlutterPlugin)) {
        throw new ClassCastException(pluginClass.getName() + " is not a FlutterPlugin");
      }
      flutterEngine.getPlugins().add((FlutterPlugin) plugin);
    } catch (ClassNotFoundException e) {
      // Normal APKs do not package integration_test; this is expected.
    } catch (ReflectiveOperationException | ClassCastException e) {
      Log.e(TAG, "Error registering plugin integration_test", e);
    }
  }
}
