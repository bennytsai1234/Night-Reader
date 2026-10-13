import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';
import 'package:night_reader/shared/widgets/glass.dart';

/// 書籍詳情底部的浮動玻璃膠囊：「開始閱讀／繼續閱讀」。目錄捲到哪都
/// 按得到。
///
/// 放在 [Scaffold.bottomNavigationBar] 並搭配 `extendBody: true`：位置與
/// 寬度照浮動分頁列（[FloatingTabBar.slotOf]：左右 16、避開底部系統區、
/// 最寬 500），清單底部讓出的 `MediaQuery.paddingOf(context).bottom`
/// 就包含它的高度，浮動提示也會停在它上方。
class BookReadCapsule extends StatelessWidget {
  const BookReadCapsule({
    super.key,
    required this.started,
    required this.visible,
    required this.onPressed,
  });

  static const double height = AppGlass.tabItemHeight;

  /// 讀過的書顯示「繼續閱讀」。
  final bool started;

  /// 載入完成才出現；隱藏時仍佔著位置，清單底部不會跟著跳動。
  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final slot = FloatingTabBar.slotOf(context);
    final label = started ? '繼續閱讀' : '開始閱讀';
    return Padding(
      padding: slot,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.fade,
        curve: AppMotion.fadeCurve,
        child: IgnorePointer(
          ignoring: !visible,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppGlass.tabBarMaxWidth,
              ),
              child: Semantics(
                button: true,
                label: label,
                excludeSemantics: true,
                child: PressScale(
                  scale: 0.97,
                  onTap: onPressed,
                  child: SizedBox(
                    height: height,
                    child: GlassSurface(
                      borderRadius: AppRadius.pillShape,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.menu_book_rounded,
                            size: 22,
                            color: primary,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            label,
                            style: AppTextStyles.uiMd.copyWith(
                              fontWeight: FontWeight.w600,
                              color: primary,
                            ),
                          ),
                        ],
                      ),
                    ),
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
