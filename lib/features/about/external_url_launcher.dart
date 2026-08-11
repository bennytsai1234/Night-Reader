import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> launchExternalUrlWithFeedback(
  BuildContext context,
  String url, {
  Future<bool> Function(Uri uri)? launcher,
}) async {
  try {
    final uri = Uri.parse(url);
    final opened =
        launcher == null
            ? await launchUrl(uri, mode: LaunchMode.externalApplication)
            : await launcher(uri);
    if (opened) {
      return true;
    }
    AppLog.d('無法開啟連結: $url');
  } catch (error, stackTrace) {
    AppLog.e('開啟外部連結失敗: $url', error: error, stackTrace: stackTrace);
  }

  if (!context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('無法開啟連結'),
        action: SnackBarAction(
          label: '複製連結',
          onPressed: () async {
            try {
              await Clipboard.setData(ClipboardData(text: url));
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('已複製連結')));
            } catch (error, stackTrace) {
              AppLog.e('複製外部連結失敗: $url', error: error, stackTrace: stackTrace);
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('複製連結失敗')));
            }
          },
        ),
      ),
    );
  return false;
}
