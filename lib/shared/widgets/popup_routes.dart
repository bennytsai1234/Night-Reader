import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

/// 彈出層從哪裡打開、裡面套什麼主題。
///
/// 彈出層的路由會把打開處到 Navigator 之間的主題複製一份定住
/// （[InheritedTheme.capture]）。從底部面板裡打開時，複製到的是面板那一階
/// 主題（[sheetThemeOf]）在面板打開當下的樣子，之後系統切換深淺也不跟著換。
/// 所以從面板裡打開時改從面板外層（套面板主題之前，[RaisedSheetScope]）
/// 打開，進了新的路由再照當下的主題墊上面板那一階（[wrap]）。
@immutable
class PopupOrigin {
  const PopupOrigin._(this.context, {required this.raised});

  factory PopupOrigin.of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<RaisedSheetScope>();
    return scope == null
        ? PopupOrigin._(context, raised: false)
        : PopupOrigin._(scope.base, raised: true);
  }

  /// 拿來找 Navigator、複製主題的位置。
  final BuildContext context;

  /// 從墊高一階的底部面板裡打開：路由裡要照當下主題再墊一階。
  final bool raised;

  /// 把彈出層的內容包在打開處的主題裡。
  Widget wrap(Widget child) => raised ? RaisedSheetTheme(child: child) : child;
}

/// 套上當下主題墊高一階的面板主題（[sheetThemeOf]），系統切換深淺時跟著換。
class RaisedSheetTheme extends StatelessWidget {
  const RaisedSheetTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: sheetThemeOf(Theme.of(context)), child: child);
}

/// 標出墊高一階的底部面板，記住面板主題套上之前的位置（[base]）；面板裡
/// 打開的彈出層從那裡打開（[PopupOrigin]）。
class RaisedSheetScope extends InheritedWidget {
  const RaisedSheetScope({super.key, required this.base, required super.child});

  final BuildContext base;

  @override
  bool updateShouldNotify(RaisedSheetScope oldWidget) => false;
}

/// 彈出層的遮罩照當下主題取色（[AppChrome.barrier]），系統切換深淺時跟著
/// 換；[themes] 是打開處的主題，取到的顏色和在打開處取的一樣。
///
/// 路由的遮罩色本來在打開時就定住；這裡在建遮罩時先照當下主題記下顏色，
/// 再交給路由原本的遮罩（淡入淡出照舊）。
Widget _liveBarrier(
  CapturedThemes themes,
  void Function(Color color) remember,
  Widget Function() build,
) => themes.wrap(
  Builder(
    builder: (context) {
      remember(AppChrome.of(context).barrier);
      return build();
    },
  ),
);

/// 底部面板與動作表的路由：遮罩跟著當下主題（[_liveBarrier]），其餘照
/// [showModalBottomSheet]。
class _AppSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _AppSheetRoute({
    required super.builder,
    required CapturedThemes super.capturedThemes,
    required super.isScrollControlled,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.backgroundColor,
    super.elevation,
    super.shape,
    super.clipBehavior,
    super.constraints,
    super.isDismissible,
    super.enableDrag,
    super.showDragHandle,
    super.useSafeArea,
    required this._barrier,
    required this.liveBarrier,
  });

  /// 遮罩照主題取色（[AppChrome.barrier]）；呼叫端自己指定顏色時是 false，
  /// 一直用那個顏色。
  final bool liveBarrier;

  Color _barrier;

  @override
  Color get barrierColor => _barrier;

  @override
  Widget buildModalBarrier() {
    if (!liveBarrier) return super.buildModalBarrier();
    return _liveBarrier(
      capturedThemes!,
      (color) => _barrier = color,
      super.buildModalBarrier,
    );
  }
}

/// 照 [showModalBottomSheet] 打開底部面板，但從 [PopupOrigin] 打開、遮罩
/// 跟著當下主題（[_AppSheetRoute]）。[builder] 拿到的位置在面板路由裡，要
/// 自己套 [PopupOrigin.wrap]。
Future<T?> pushAppSheet<T>({
  required PopupOrigin origin,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool? showDragHandle,
  String? barrierLabel,
  Color? backgroundColor,
  Color? barrierColor,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
}) {
  final context = origin.context;
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push(
    _AppSheetRoute<T>(
      builder: builder,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: isScrollControlled,
      barrierLabel: barrierLabel ?? localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      backgroundColor: backgroundColor,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      isDismissible: isDismissible,
      // 不能點外面關掉時也不能往下拉掉（例如還沒儲存的表單）。
      enableDrag: isDismissible,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
      barrier: barrierColor ?? AppChrome.of(context).barrier,
      liveBarrier: barrierColor == null,
    ),
  );
}

/// 提示框這類對話框路由的遮罩跟著當下主題（[_liveBarrier]）；[barrierThemes]
/// 是打開處的主題。
///
/// 遮罩色在打開時先記成打開處的顏色（[RawDialogRoute] 的 `barrierColor`）。
mixin LiveDialogBarrier<T> on RawDialogRoute<T> {
  CapturedThemes get barrierThemes;

  late Color? _barrier = super.barrierColor;

  @override
  Color? get barrierColor => _barrier;

  @override
  Widget buildModalBarrier() => _liveBarrier(
    barrierThemes,
    (color) => _barrier = color,
    super.buildModalBarrier,
  );
}

/// 照 [showDialog] 打開 Material 對話框，但從 [PopupOrigin] 打開、遮罩
/// 跟著當下主題（[AppChrome.barrier]）。
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final origin = PopupOrigin.of(context);
  final navigator = Navigator.of(origin.context, rootNavigator: true);
  final themes = InheritedTheme.capture(
    from: origin.context,
    to: navigator.context,
  );
  return navigator.push<T>(
    _AppDialogRoute<T>(
      context: origin.context,
      builder: (context) => origin.wrap(builder(context)),
      themes: themes,
      barrierThemes: themes,
      barrierColor: AppChrome.of(context).barrier,
      barrierDismissible: barrierDismissible,
    ),
  );
}

class _AppDialogRoute<T> extends DialogRoute<T> with LiveDialogBarrier<T> {
  _AppDialogRoute({
    required super.context,
    required super.builder,
    required super.themes,
    required this.barrierThemes,
    required Color super.barrierColor,
    required super.barrierDismissible,
  }) : super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);

  @override
  final CapturedThemes barrierThemes;
}
