import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

/// 從外層主題算出一層自己的主題：底部面板墊高一階（[sheetThemeOf]）、
/// 閱讀選單的配色。
typedef ThemeDerivation = ThemeData Function(ThemeData base);

/// 彈出層從哪裡打開、裡面套什麼主題。
///
/// 彈出層的路由會把打開處到 Navigator 之間的主題複製一份定住
/// （[InheritedTheme.capture]）。從 [DerivedTheme] 底下打開時，複製到的是
/// 那一層主題在它打開當下的樣子，之後系統切換深淺也不跟著換。所以改從那一層
/// 的外面（[DerivedThemeScope.base]）打開，進了新的路由再照當下的主題算出
/// 那一層（[wrap]）。
@immutable
class PopupOrigin {
  const PopupOrigin._(this.context, this.derive);

  factory PopupOrigin.of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<DerivedThemeScope>();
    // 那一層和打開處之間隔著另一個 Navigator 時，從外面打開會推到別的
    // Navigator 上，照原本的位置打開。
    if (scope == null ||
        Navigator.maybeOf(context) != Navigator.maybeOf(scope.base)) {
      return PopupOrigin._(context, null);
    }
    return PopupOrigin._(scope.base, scope.derive);
  }

  /// 拿來找 Navigator、複製主題的位置。
  final BuildContext context;

  /// 打開處那一層主題怎麼從 [context] 的主題算出來；null 是不用另外算。
  final ThemeDerivation? derive;

  /// 把彈出層的內容包在打開處的主題裡。
  Widget wrap(Widget child) {
    final derive = this.derive;
    return derive == null ? child : DerivedTheme(derive: derive, child: child);
  }

  /// [context] 底下的位置在打開處會看到的主題。
  ThemeData themeOf(BuildContext context) {
    final theme = Theme.of(context);
    return derive?.call(theme) ?? theme;
  }
}

/// 照外層當下的主題算出這一層的主題（[derive]），系統切換深淺時跟著換；
/// 底下打開的彈出層從這一層外面打開、再照當下的主題算一次
/// （[PopupOrigin]）。
class DerivedTheme extends StatelessWidget {
  const DerivedTheme({super.key, required this.derive, required this.child});

  final ThemeDerivation derive;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 同一個路由裡疊了好幾層時，從最外層外面打開、依序算每一層。
    final outer = context.getInheritedWidgetOfExactType<DerivedThemeScope>();
    return DerivedThemeScope(
      base: outer?.base ?? context,
      derive: outer == null ? derive : (base) => derive(outer.derive(base)),
      child: Theme(data: derive(Theme.of(context)), child: child),
    );
  }
}

/// 記住 [DerivedTheme] 套上之前的位置（[base]）與怎麼算出那一層（[derive]）。
class DerivedThemeScope extends InheritedWidget {
  const DerivedThemeScope({
    super.key,
    required this.base,
    required this.derive,
    required super.child,
  });

  final BuildContext base;
  final ThemeDerivation derive;

  @override
  bool updateShouldNotify(DerivedThemeScope oldWidget) => false;
}

/// 彈出層的遮罩照當下主題取色（[AppChrome.barrier]），系統切換深淺時跟著
/// 換；[themes] 是打開處複製的主題，[derive] 是打開處那一層，取到的顏色和
/// 在打開處取的一樣。
///
/// 路由的遮罩色本來在打開時就定住；這裡在建遮罩時先照當下主題記下顏色，
/// 再交給路由原本的遮罩（淡入淡出照舊）。
Widget _liveBarrier(
  CapturedThemes themes,
  ThemeDerivation? derive,
  void Function(Color color) remember,
  Widget Function() build,
) => themes.wrap(
  Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final derived = derive?.call(theme).extension<AppChrome>();
      remember((derived ?? AppChrome.of(context)).barrier);
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
    required this.derive,
  });

  /// 打開處那一層主題（[PopupOrigin.derive]）。
  final ThemeDerivation? derive;

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
      derive,
      (color) => _barrier = color,
      super.buildModalBarrier,
    );
  }
}

/// 照 [showModalBottomSheet] 打開底部面板，但從 [PopupOrigin] 打開、遮罩
/// 跟著當下主題（[_AppSheetRoute]）。[builder] 拿到的位置在面板路由裡，
/// 內容要自己包 [PopupOrigin.wrap]。
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
      derive: origin.derive,
    ),
  );
}

/// 提示框這類對話框路由的遮罩跟著當下主題（[_liveBarrier]）；[barrierThemes]
/// 是打開處的主題。
///
/// 遮罩色在打開時先記成打開處的顏色（[RawDialogRoute] 的 `barrierColor`）。
mixin LiveDialogBarrier<T> on RawDialogRoute<T> {
  CapturedThemes get barrierThemes;

  /// 打開處那一層主題（[PopupOrigin.derive]）。
  ThemeDerivation? get barrierDerive;

  late Color? _barrier = super.barrierColor;

  @override
  Color? get barrierColor => _barrier;

  @override
  Widget buildModalBarrier() => _liveBarrier(
    barrierThemes,
    barrierDerive,
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
      builder: (context) => origin.wrap(Builder(builder: builder)),
      themes: themes,
      barrierThemes: themes,
      barrierDerive: origin.derive,
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
    required this.barrierDerive,
    required Color super.barrierColor,
    required super.barrierDismissible,
  }) : super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);

  @override
  final CapturedThemes barrierThemes;

  @override
  final ThemeDerivation? barrierDerive;
}
