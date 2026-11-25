import 'dart:async';

import 'package:night_reader/core/app_lock/app_lock.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:app_links/app_links.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'handlers/association_base.dart';
import 'handlers/uri_association_handler.dart';
import 'handlers/file_association_handler.dart';
import 'handlers/association_dialog_helper.dart';

export 'handlers/association_base.dart';
export 'handlers/uri_association_handler.dart';
export 'handlers/file_association_handler.dart';
export 'handlers/association_dialog_helper.dart';

/// AssociationHandlerService - 外部連結與分享處理服務 (重構後)
/// (原 Android ui/main/IntentHandler.kt)
class AssociationHandlerService extends AssociationBase
    with
        UriAssociationHandler,
        FileAssociationHandler,
        AssociationDialogHelper {
  static final AssociationHandlerService _instance =
      AssociationHandlerService._internal();
  factory AssociationHandlerService() => _instance;
  AssociationHandlerService._internal();

  @override
  void init(
    BuildContext context, {
    Function(BuildContext, Uri)? onUri,
    Function(BuildContext, List<dynamic>)? onMedia,
  }) {
    appLinks = AppLinks();

    // 1. Deep Link (legado://、yuedu://)：app_links 6 起這個串流也會送出開啟
    // App 的那個連結，不另外呼叫 getInitialLink()，否則冷啟動會跳兩次匯入。
    // 「離開時」選了會解鎖的選項時，解鎖、鎖的畫面收掉之後才處理（ADR 0083）：
    // 分享進來的書不在解鎖前就加進書架。
    linkSubscription = appLinks.uriLinkStream.listen((uri) async {
      await AppLock.instance.whenOpen();
      if (context.mounted) handleUri(context, uri);
    });

    // 2. Sharing Intent (File/Text)
    sharedMediaSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((value) async {
          await AppLock.instance.whenOpen();
          if (context.mounted) unawaited(handleSharedMedia(context, value));
        }, onError: (err) => AppLog.e('SharingIntent error: $err', error: err));

    // Check initial intents
    // Initial-intent futures are intentionally fire-and-forget because this
    // lifecycle hook cannot delay the first frame.  They still need explicit
    // error handlers: a plugin failure here otherwise becomes an uncaught
    // asynchronous error during startup.
    ReceiveSharingIntent.instance.getInitialMedia().then(
      (value) async {
        if (value.isEmpty) return;
        await AppLock.instance.whenOpen();
        if (context.mounted) unawaited(handleSharedMedia(context, value));
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLog.e(
          'Initial sharing intent failed: $error',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }
}
