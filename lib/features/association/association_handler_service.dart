import 'package:flutter/material.dart';
import 'package:reader/core/services/app_log_service.dart';
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

    // 1. Deep Link (legado://)
    linkSubscription = appLinks.uriLinkStream.listen((uri) {
      if (context.mounted) handleUri(context, uri, showImportDialog);
    });

    // 2. Sharing Intent (File/Text)
    sharedMediaSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((value) {
          if (context.mounted)
            handleSharedMedia(
              context,
              value,
              showImportDialog,
              (ctx, path) => showForceImportDialog(ctx, path, handleSharedBook),
            );
        }, onError: (err) => AppLog.e('SharingIntent error: $err', error: err));

    // Check initial intents
    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty && context.mounted)
        handleSharedMedia(
          context,
          value,
          showImportDialog,
          (ctx, path) => showForceImportDialog(ctx, path, handleSharedBook),
        );
    });

    appLinks.getInitialLink().then((uri) {
      if (uri != null && context.mounted)
        handleUri(context, uri, showImportDialog);
    });
  }
}
