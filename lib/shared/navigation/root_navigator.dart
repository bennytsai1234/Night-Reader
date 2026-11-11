import 'package:flutter/widgets.dart';

/// App 最外層的 Navigator：不在任何頁面裡、要推頁面時用（例如點背景工作的
/// 通知回到那一頁，ADR 0058）。
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
