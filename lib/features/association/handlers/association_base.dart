import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';

/// AssociationHandlerService 的基礎狀態與生命週期定義
abstract class AssociationBase {
  late AppLinks appLinks;
  StreamSubscription? linkSubscription;
  StreamSubscription? sharedMediaSubscription;

  void init(
    BuildContext context, {
    required Function(BuildContext, Uri) onUri,
    required Function(BuildContext, List<dynamic>) onMedia,
  });

  void dispose() {
    linkSubscription?.cancel();
    sharedMediaSubscription?.cancel();
  }
}
