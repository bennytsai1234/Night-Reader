import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_chrome.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';
import 'launch_entrance.dart';

/// 霧面紙材質：紙／墨色調、輕度背景模糊、髮絲亮邊與漫射陰影。
///
/// 色調本身約 84% 不透明，即使模糊被降級仍像一張紙面，不會變成透明。
/// 模糊走 [BackdropFilter.grouped]，同一 [BackdropGroup] 下的多塊玻璃共用
/// 一次背景取樣。
///
/// 不要包在 [Opacity]、[FadeTransition] 或 [AnimatedOpacity] 裡（ADR 0022）：
/// 透明度不到 1 時模糊取不到底下的畫面，到 1 的那一幀才突然糊上去。玻璃
/// 進出場用 [GlassSlide] 滑動；要淡入淡出時包 [GlassReveal]。
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.tint,
    this.shadow = true,
    this.blur = true,
    this.grouped = true,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final BoxShape shape;

  /// 覆寫色調（例如閱讀器選單用選單主題色）；需自帶透明度。
  final Color? tint;
  final bool shadow;
  final bool blur;

  /// 與同一頁的其他玻璃共用背景取樣。疊在其他玻璃上方的元件（選單、
  /// 面板）要設為 false，重疊區域共用取樣會只模糊一次。
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    // 在 [GlassMorph] 裡：玻璃由外面那塊共用，這裡只畫內容。
    if (_GlassMorphContent._inside(context)) {
      return _GlassMorphContent._reset(child: child);
    }
    final reveal = GlassReveal._of(context);
    // 裡面的玻璃不再跟著淡：內容已經整塊淡入，再淡一次會變成平方。
    if (reveal == null) return _build(context, 1, child);
    final inner = GlassReveal._reset(child: child);
    return AnimatedBuilder(
      animation: reveal,
      // 內容跟著淡入。只在淡入的玻璃包 Opacity：透明度 1 時它仍會多開一層
      // 圖層，平常的玻璃不必付這個成本。
      builder: (context, _) => _build(
        context,
        reveal.value,
        Opacity(opacity: reveal.value, child: inner),
      ),
    );
  }

  /// [shown] 0→1：色調、亮邊、模糊強度與陰影一起從無到有；每個 [shown]
  /// 建出的元件樹相同，進出場中內容的狀態不會丟。
  Widget _build(BuildContext context, double shown, Widget child) {
    final chrome = AppChrome.of(context);
    final radius = shape == BoxShape.circle ? null : borderRadius;
    final color = tint ?? chrome.glassTint;
    final decoration = BoxDecoration(
      color: color.withValues(alpha: color.a * shown),
      shape: shape,
      borderRadius: radius,
      border: Border.all(
        color: chrome.glassBorder.withValues(
          alpha: chrome.glassBorder.a * shown,
        ),
        width: AppGlass.hairline,
      ),
    );
    Widget content = DecoratedBox(decoration: decoration, child: child);
    final sigma = chrome.glassStrength.blur * shown;
    if (blur && chrome.glassStrength.blur > 0) {
      final filter = ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
      content = grouped
          ? BackdropFilter.grouped(filter: filter, child: content)
          : BackdropFilter(filter: filter, child: content);
    }
    content = shape == BoxShape.circle
        ? ClipOval(child: content)
        : ClipRRect(borderRadius: radius ?? BorderRadius.zero, child: content);
    if (!shadow) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: chrome.glassShadow.withValues(
              alpha: chrome.glassShadow.a * shown,
            ),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: content,
    );
  }
}

/// 讓底下最近的一塊 [GlassSurface] 隨 [animation]（0→1）淡入淡出：色調、
/// 亮邊、模糊強度與陰影一起變，內容跟著淡，最後一幀就是靜止的玻璃
/// （ADR 0022）。用在原地出現、不從畫面外滑進來的玻璃（提示框）。
class GlassReveal extends InheritedWidget {
  const GlassReveal({
    super.key,
    required Animation<double> this.animation,
    required super.child,
  });

  const GlassReveal._reset({required super.child}) : animation = null;

  final Animation<double>? animation;

  static Animation<double>? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassReveal>()?.animation;

  @override
  bool updateShouldNotify(GlassReveal oldWidget) =>
      animation != oldWidget.animation;
}

/// 同一個位置換按鈕時（例如頁首進出多選：「整理」圓鈕換成「完成」膠囊），
/// 玻璃留著不動、只改大小，裡面的圖示或文字交叉淡換（ADR 0022：玻璃只動、
/// 內容只淡）。
///
/// [child] 是一顆玻璃按鈕（[GlassIconButton]、[GlassTextButton]、
/// `GlassMenuButton`）：它自己的那塊玻璃交給這裡共用，只畫內容。換成不同
/// 的按鈕（種類、圖示或文字不同）時交叉淡換，玻璃的寬度在同一段時間裡
/// 連續變到新按鈕的寬度；圓鈕就是最窄的膠囊，兩者共用同一塊膠囊形玻璃。
/// 不要放非玻璃的元件：它背後也會多出一塊玻璃。
///
/// [child] 為 null 時這個位置沒有按鈕：玻璃縮成一個點。換成有按鈕時玻璃從
/// 那個點長大，拿掉時縮回去，不淡（ADR 0022）。
class GlassMorph extends StatelessWidget {
  const GlassMorph({super.key, required this.child});

  final Widget? child;

  /// 判斷是不是換了一顆按鈕：同種類但圖示或文字不同也算。
  static Object _identityOf(Widget child) => switch (child) {
    GlassTextButton(:final label, :final emphasized) => (
      GlassTextButton,
      label,
      emphasized,
    ),
    GlassIconButton(:final icon, :final label) => (
      GlassIconButton,
      icon,
      label,
    ),
    _ => (child.runtimeType, child.key),
  };

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.fade;
    return GlassSurface(
      borderRadius: AppRadius.pillShape,
      shadow: false,
      child: AnimatedSize(
        duration: duration,
        curve: AppMotion.fadeCurve,
        child: AnimatedSwitcher(
          duration: duration,
          switchInCurve: AppMotion.fadeCurve,
          switchOutCurve: AppMotion.fadeCurve,
          // 大小只照新按鈕：舊的縮成 0×0 的錨點、從中央溢出畫，外面的
          // AnimatedSize 一開始淡換就往新寬度走，不會等舊的淡完才縮。淡出
          // 中的舊按鈕不接點擊、不給讀屏念。
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              for (final child in previous)
                SizedBox.shrink(
                  child: OverflowBox(
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: IgnorePointer(child: ExcludeSemantics(child: child)),
                  ),
                ),
              ?current,
            ],
          ),
          child: switch (child) {
            final child? => _GlassMorphContent(
              key: ValueKey(_identityOf(child)),
              child: child,
            ),
            null => const SizedBox.shrink(key: ValueKey(GlassMorph)),
          },
        ),
      ),
    );
  }
}

/// 標出 [GlassMorph] 的內容：底下最近的一塊 [GlassSurface] 不畫自己的玻璃。
class _GlassMorphContent extends InheritedWidget {
  const _GlassMorphContent({super.key, required super.child}) : inside = true;

  const _GlassMorphContent._reset({required super.child}) : inside = false;

  final bool inside;

  static bool _inside(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_GlassMorphContent>()
          ?.inside ??
      false;

  @override
  bool updateShouldNotify(_GlassMorphContent oldWidget) =>
      inside != oldWidget.inside;
}

/// 玻璃從畫面 [edge] 那一側滑進滑出，不淡（ADR 0022）。
///
/// [shown] 為 0 時完全在畫面外：移開自身大小，再加上離螢幕邊緣的 [gap] 與
/// 陰影伸出的 [AppGlass.shadowReach]；這時不畫、不接點擊也不進讀屏。
class GlassSlide extends StatelessWidget {
  const GlassSlide({
    super.key,
    required this.shown,
    required this.edge,
    this.gap = 0,
    required this.child,
  });

  final double shown;
  final AxisDirection edge;
  final double gap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final away = 1 - shown;
    final unit = switch (edge) {
      AxisDirection.up => const Offset(0, -1),
      AxisDirection.down => const Offset(0, 1),
      AxisDirection.left => const Offset(-1, 0),
      AxisDirection.right => const Offset(1, 0),
    };
    return Visibility(
      visible: shown > 0,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: Transform.translate(
        offset: unit * ((gap + AppGlass.shadowReach) * away),
        child: FractionalTranslation(translation: unit * away, child: child),
      ),
    );
  }
}

/// 按下時微縮的回饋（Telegram 玻璃按鈕的按壓感）。
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.92,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: _pressed
            ? const Duration(milliseconds: 90)
            : AppMotion.spring,
        curve: _pressed ? Curves.easeOut : AppMotion.springCurve,
        child: widget.child,
      ),
    );
  }
}

/// 44×44 圓形玻璃按鈕；導航頁首兩側與閱讀器選單使用。
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.tint,
    this.size = AppGlass.buttonSize,
    this.iconSize = 22,
    this.onLongPress,
    this.label,
    this.blur = true,
  });

  final IconData icon;

  /// 放在不透明底上、跟著內容淡入時傳 false：不取樣背景，淡入中也沒有
  /// 模糊會在最後一幀才糊上（ADR 0022）。
  final bool blur;

  /// 有值時在圓鈕中央顯示這段短字，取代圖示（例如倒數的剩餘分鐘）。
  final String? label;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final Color? color;
  final Color? tint;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final foreground = (color ?? scheme.onSurface).withValues(
      alpha: enabled ? 1 : 0.38,
    );
    Widget button = PressScale(
      onTap: onPressed,
      onLongPress: onLongPress,
      child: SizedBox.square(
        dimension: size,
        child: GlassSurface(
          shape: BoxShape.circle,
          tint: tint,
          shadow: false,
          blur: blur,
          child: Center(
            child: switch (label) {
              final text? => Text(
                text,
                maxLines: 1,
                style: AppTextStyles.uiSm.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              null => Icon(icon, size: iconSize, color: foreground),
            },
          ),
        ),
      ),
    );
    button = Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: button,
    );
    if (tooltip == null) return button;
    // 名稱已由上面的 Semantics 提供；Tooltip 再提供一次，讀屏會念兩遍。
    return Tooltip(
      message: tooltip!,
      excludeFromSemantics: true,
      child: button,
    );
  }
}

/// 膠囊形玻璃文字按鈕（例如頁首的「完成」「編輯」）。
class GlassTextButton extends StatelessWidget {
  const GlassTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
    this.blur = true,
  });

  final String label;
  final VoidCallback? onPressed;

  /// 主要動作用主色字並加粗。
  final bool emphasized;

  /// 見 [GlassIconButton.blur]。
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final color = emphasized ? scheme.primary : scheme.onSurface;
    return Semantics(
      button: true,
      enabled: enabled,
      child: PressScale(
        onTap: onPressed,
        child: SizedBox(
          height: AppGlass.buttonSize,
          child: GlassSurface(
            borderRadius: AppRadius.pillShape,
            shadow: false,
            blur: blur,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: AppTextStyles.uiMd.copyWith(
                    color: color.withValues(alpha: enabled ? 1 : 0.38),
                    fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 頁首或面板上的純文字動作（Telegram 的「取消」「清除」）。
class PlainTextAction extends StatelessWidget {
  const PlainTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
    this.destructive = false,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool emphasized;
  final bool destructive;

  /// 組標題旁的小字動作。
  final bool small;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final base = destructive
        ? (Theme.of(context).brightness == Brightness.dark
              ? AppPalette.rustDark
              : AppPalette.rust)
        : scheme.primary;
    final style = (small ? AppTextStyles.uiSm : AppTextStyles.bodyBase)
        .copyWith(
          height: 1.2,
          color: base.withValues(alpha: enabled ? 1 : 0.4),
          fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
        );
    return Semantics(
      button: true,
      enabled: enabled,
      child: PressScale(
        scale: 0.95,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: small ? 28 : AppGlass.buttonSize,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: small ? 0 : AppSpacing.xs,
            ),
            child: Center(widthFactor: 1, child: Text(label, style: style)),
          ),
        ),
      ),
    );
  }
}

/// 小型玻璃膠囊（分類標籤、搜尋範圍等可點的小選項）。
///
/// 放在卡片等不透明底上時傳 `blur: false`，省下背景取樣。
class GlassCapsule extends StatelessWidget {
  const GlassCapsule({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.trailingIcon,
    this.selected = false,
    this.foregroundColor,
    this.blur = true,
    this.tint,
    this.maxLines = 1,
    this.tooltip,
    this.count,
  });

  static const double height = 34.0;

  /// 選取中的淡主色底。字也是主色，主色比例壓低才維持 4.5:1 的文字對比。
  static Color selectedTintOf(ColorScheme scheme) => Color.alphaBlend(
    scheme.primary.withValues(alpha: 0.06),
    scheme.surface.withValues(alpha: 0.9),
  );

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final IconData? trailingIcon;

  /// 開啟中的選項：主色字與淡主色底。
  final bool selected;

  /// 覆寫文字與圖示顏色（例如錯誤項目）。
  final Color? foregroundColor;
  final bool blur;

  /// 覆寫未選取時的底色（例如放在卡片上時改用分組底色，與卡片區隔）。
  final Color? tint;
  final int maxLines;
  final String? tooltip;

  /// 標籤後方的小字數量（例如分組內的書源數）。
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final color =
        (foregroundColor ?? (selected ? scheme.primary : scheme.onSurface))
            .withValues(alpha: enabled ? 1 : 0.45);
    final style = AppTextStyles.uiSm.copyWith(
      color: color,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    );

    Widget capsule = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: height),
      child: GlassSurface(
        borderRadius: AppRadius.pillShape,
        shadow: false,
        blur: blur,
        tint: selected ? selectedTintOf(scheme) : tint,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md + 2,
            vertical: AppSpacing.xs + 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: color),
                const SizedBox(width: AppSpacing.xs),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: style,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '$count',
                  style: AppTextStyles.uiXs.copyWith(
                    color: color.withValues(alpha: color.a * 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (trailingIcon != null) ...[
                const SizedBox(width: 2),
                Icon(trailingIcon, size: 16, color: color),
              ],
            ],
          ),
        ),
      ),
    );
    capsule = Semantics(
      button: enabled,
      selected: selected,
      label: tooltip,
      child: PressScale(scale: 0.95, onTap: onTap, child: capsule),
    );
    if (tooltip == null) return capsule;
    return Tooltip(
      message: tooltip!,
      excludeFromSemantics: true,
      child: capsule,
    );
  }
}

/// 浮在清單底部的膠囊玻璃工具列（編輯模式的批次動作列）；置中、最寬同
/// 浮動分頁列。左右外距與底部安全區由呼叫端決定。
class FloatingGlassToolbar extends StatelessWidget {
  const FloatingGlassToolbar({
    super.key,
    required this.child,
    this.height = AppGlass.tabItemHeight,
  });

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppGlass.tabBarMaxWidth),
        child: SizedBox(
          height: height,
          child: GlassSurface(
            borderRadius: AppRadius.pillShape,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 內容捲到浮動列底下時的邊緣漸隱。
class EdgeFade extends StatelessWidget {
  const EdgeFade({
    super.key,
    required this.edge,
    required this.height,
    this.color,
    this.solidFraction = 0,
  });

  /// [AxisDirection.up] 表示貼在上緣（由上往下淡出）。
  final AxisDirection edge;
  final double height;
  final Color? color;

  /// 從邊緣起算保持實色的比例。
  final double solidFraction;

  @override
  Widget build(BuildContext context) {
    final base = color ?? Theme.of(context).scaffoldBackgroundColor;
    final top = edge == AxisDirection.up;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              // 中段的透明度以底色本身的透明度為準：呼叫端可以整條淡出，
              // 半透明的底色（例如書籍詳情頁頂透出封面氛圍時）漸隱時也不會
              // 比實色段更深。
              colors: [
                base,
                base,
                base.withValues(alpha: base.a * 0.72),
                base.withValues(alpha: 0),
              ],
              stops: [
                0,
                solidFraction,
                solidFraction + (1 - solidFraction) * 0.45,
                1,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Telegram 式導航頁首：置中標題、兩側圓形玻璃按鈕、下緣漸隱，無實心底板與
/// 分隔線。
///
/// 作為 [Scaffold.appBar] 使用。頁面搭配 `extendBodyBehindAppBar: true` 時，
/// 內容會捲到頁首底下並在下緣淡出；此時清單需讓出
/// `MediaQuery.paddingOf(context).top`（未指定 padding 的 ScrollView 會自動
/// 處理）。不延伸時頁首就是一段與背景同色的平整區域。
///
/// 標題、兩側按鈕都沒有、也不自動放返回鈕時，不留工具列的高度，只剩狀態列
/// 與下緣漸隱（例如「我的」分頁）。標題一律置中，不用靠左的大標題（ADR 0011）。
class GlassNavHeader extends StatelessWidget implements PreferredSizeWidget {
  const GlassNavHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions = const [],
    this.automaticallyImplyLeading = true,
    this.bottom,
    this.bottomHeight = 0,
    this.backgroundColor,
    this.foregroundColor,
    this.systemOverlayStyle,
    this.titleSheen = false,
    this.morph = false,
  });

  /// 同一頁在兩種頁首之間切換（例如進出多選）時連續過渡：標題交叉淡換，
  /// 左右兩側每個位置的按鈕包在 [GlassMorph] 裡，玻璃留著只改大小、內容
  /// 淡換。兩種頁首都要設 true，兩側也都只能放玻璃按鈕。一側在其中一種頁首
  /// 沒有按鈕時，那個位置的玻璃從一個點長大或縮回去；右側兩種頁首都有按鈕
  /// 時，按鈕數要一樣。
  final bool morph;

  final String? title;
  final Widget? titleWidget;

  /// 覆寫左側按鈕；為 null 且可返回時自動放返回鈕。
  final Widget? leading;
  final List<Widget> actions;
  final bool automaticallyImplyLeading;

  /// 標題列下方附加的內容（例如分段控制、搜尋框、橫向分頁）。
  final Widget? bottom;
  final double bottomHeight;

  /// 漸隱底色；預設為 scaffold 背景色。
  final Color? backgroundColor;
  final Color? foregroundColor;
  final SystemUiOverlayStyle? systemOverlayStyle;

  /// 標題字樣上掃過淡墨流光，表示背景作業進行中（見 [InkSheen]）。
  final bool titleSheen;

  bool get _hasToolbar =>
      title != null ||
      titleWidget != null ||
      leading != null ||
      actions.isNotEmpty ||
      automaticallyImplyLeading;

  double get _toolbarHeight => _hasToolbar ? AppGlass.headerToolbarHeight : 0;

  @override
  Size get preferredSize => Size.fromHeight(
    _toolbarHeight + bottomHeight + AppGlass.headerFadeHeight,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;
    final bg = backgroundColor ?? theme.scaffoldBackgroundColor;
    final fg = foregroundColor ?? theme.colorScheme.onSurface;
    final route = ModalRoute.of(context);
    final canPop = route?.impliesAppBarDismissal ?? false;
    final effectiveLeading =
        leading ??
        (automaticallyImplyLeading && canPop
            ? GlassIconButton(
                icon: route is PageRoute && route.fullscreenDialog
                    ? Icons.close_rounded
                    : Icons.arrow_back_ios_new_rounded,
                iconSize: 20,
                tooltip: '返回',
                color: fg,
                onPressed: () => Navigator.maybePop(context),
              )
            : null);
    final solidHeight = topPadding + _toolbarHeight + bottomHeight;
    final totalHeight = solidHeight + AppGlass.headerFadeHeight;
    final brightness = ThemeData.estimateBrightnessForColor(bg);
    // 開 App 的進場：標題與按鈕先是骨架，跟書架一起換成真的。
    // 左側位置的高度是撐滿工具列的；置中讓玻璃照按鈕自己的大小，不被拉高。
    Widget slot(Widget? button) => morph
        ? Center(
            widthFactor: 1,
            child: LaunchSkeleton(child: GlassMorph(child: button)),
          )
        : LaunchSkeleton(child: button!);
    // 連續過渡時沒有按鈕的一側也留著位置，按鈕才能從一個點長出來。
    final hasLeading = effectiveLeading != null || morph;
    final trailing = morph && actions.isEmpty ? const <Widget?>[null] : actions;
    Widget? middle =
        titleWidget ??
        (title == null
            ? null
            : NavHeaderTitle(
                title!,
                key: morph ? ValueKey(title) : null,
                color: fg,
                sheen: titleSheen,
              ));
    if (morph && middle != null) {
      final duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.fade;
      middle = AnimatedSwitcher(
        duration: duration,
        switchInCurve: AppMotion.fadeCurve,
        switchOutCurve: AppMotion.fadeCurve,
        child: middle,
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          systemOverlayStyle ??
          (brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark),
      child: SizedBox(
        height: totalHeight,
        child: Stack(
          children: [
            Positioned.fill(
              child: EdgeFade(
                edge: AxisDirection.up,
                height: totalHeight,
                color: bg,
                solidFraction: (solidHeight - AppSpacing.xs) / totalHeight,
              ),
            ),
            if (_hasToolbar)
              Positioned(
                top: topPadding,
                left: 0,
                right: 0,
                height: AppGlass.headerToolbarHeight,
                child: NavigationToolbar(
                  middleSpacing: AppSpacing.md,
                  leading: !hasLeading
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(
                            left: AppGrouped.margin,
                          ),
                          child: IconTheme.merge(
                            data: IconThemeData(color: fg),
                            child: slot(effectiveLeading),
                          ),
                        ),
                  middle: middle == null
                      ? null
                      : LaunchSkeleton.text(
                          textStyle: AppTextStyles.titleSm,
                          child: middle,
                        ),
                  trailing: trailing.isEmpty
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(
                            right: AppGrouped.margin,
                          ),
                          child: IconTheme.merge(
                            data: IconThemeData(color: fg),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < trailing.length; i++) ...[
                                  if (i > 0)
                                    const SizedBox(width: AppSpacing.sm),
                                  slot(trailing[i]),
                                ],
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            if (bottom != null)
              Positioned(
                top: topPadding + _toolbarHeight,
                left: 0,
                right: 0,
                height: bottomHeight,
                child: bottom!,
              ),
          ],
        ),
      ),
    );
  }
}

/// 頁首置中的小標題（18／w600）。
///
/// [visible] 為 false 時透明且讀屏略過，切換時以 [AppMotion.fade] 淡入淡出：
/// 頁面頂端已經有書名（書籍詳情的封面區）時先藏起來，那一區捲進頁首底下
/// 後才由它接手。
class NavHeaderTitle extends StatelessWidget {
  const NavHeaderTitle(
    this.title, {
    super.key,
    this.visible = true,
    this.color,
    this.sheen = false,
  });

  final String title;
  final bool visible;

  /// 預設為主要文字色。
  final Color? color;

  /// 見 [InkSheen]。
  final bool sheen;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      excluding: !visible,
      child: Semantics(
        header: true,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppMotion.fade,
          curve: AppMotion.fadeCurve,
          child: InkSheen(
            active: sheen,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleSm.copyWith(
                fontWeight: FontWeight.w600,
                color: color ?? Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 背景作業進行中時，從左到右反覆掃過文字的一道淡墨流光（書架檢查更新時
/// 的「書架」字樣）。
///
/// [active] 轉為 false 後把正在掃的這一輪掃完才停；系統關閉動畫時不播。
/// 只在掃動時包一層 [ShaderMask]（範圍只有這段文字），平時就是原本的文字。
class InkSheen extends StatefulWidget {
  const InkSheen({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<InkSheen> createState() => _InkSheenState();
}

class _InkSheenState extends State<InkSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.sheen,
  )..addStatusListener(_onStatus);

  bool _animationsDisabled = false;

  bool get _shouldRun => widget.active && !_animationsDisabled;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _shouldRun) {
      _controller.forward(from: 0);
    }
  }

  void _sync() {
    if (_animationsDisabled) {
      _controller.stop();
      return;
    }
    // 停用時不打斷：這一輪掃完後 [_onStatus] 不再重新開始。
    if (_shouldRun && !_controller.isAnimating) _controller.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsDisabled = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(InkSheen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheen = Theme.of(context).colorScheme.onSurfaceVariant
        .withValues(alpha: 0.7);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        if (!_controller.isAnimating) return child!;
        // 光帶寬約字樣的一半，中心從左緣外掃到右緣外，頭尾都看不到光帶。
        const halfBand = 0.5;
        final center =
            -1 - halfBand * 2 + _controller.value * (2 + halfBand * 4);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(center - halfBand * 2, 0),
            end: Alignment(center + halfBand * 2, 0),
            colors: [
              sheen.withValues(alpha: 0),
              sheen,
              sheen.withValues(alpha: 0),
            ],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}
