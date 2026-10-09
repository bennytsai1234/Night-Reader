import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_palette.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/glass.dart';

/// 閱讀器內設定面板的唯一開啟入口。
///
/// 面板配色取閱讀選單配色（[ReaderV2MenuStyle]），面板開啟期間換風格或
/// 深淺會即時更新；設定變動時整個面板重建，內容不必各自監聽。
class ReaderV2MenuSheet {
  const ReaderV2MenuSheet._();

  static Future<T?> show<T>(
    BuildContext context, {
    required ReaderV2SettingsController settings,
    required WidgetBuilder builder,
    Color? barrierColor,
  }) {
    return AppBottomSheet.showCustom<T>(
      context: context,
      isScrollControlled: true,
      // 面板底色由下方 Material 依選單主題繪製，才能在開啟期間即時換色。
      backgroundColor: Colors.transparent,
      barrierColor: barrierColor,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.topSheetXl),
      builder: (sheetContext) => ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final theme = ReaderV2MenuStyle.of(context)
              .toSheetTheme(Theme.of(context));
          return Theme(
            data: theme,
            child: Material(
              color: theme.colorScheme.surface,
              child: DefaultTextStyle.merge(
                style: TextStyle(color: theme.colorScheme.onSurface),
                child: Builder(builder: builder),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 閱讀器設定面板的版面：拖曳把手、置中標題與右側圓形關閉鈕，
/// 下方為可捲動內容。配色取自 [ReaderV2MenuSheet] 套上的選單主題。
class ReaderV2SheetScaffold extends StatelessWidget {
  const ReaderV2SheetScaffold({
    super.key,
    required this.title,
    required this.children,
    this.maxHeightFactor = 0.9,
  });

  final String title;
  final List<Widget> children;

  /// 面板最大高度佔螢幕高度的比例；需要同時看到正文的面板使用較小值。
  final double maxHeightFactor;

  static const double _handleWidth = 36;
  static const double _handleHeight = 5;
  static const double _closeSize = 30;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * maxHeightFactor;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: AppSpacing.sm),
                width: _handleWidth,
                height: _handleHeight,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: AppRadius.pillShape,
                ),
              ),
            ),
            SizedBox(
              height: AppGlass.headerToolbarHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    // 左右讓出關閉鈕的寬度，標題才能真正置中。
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppGrouped.margin + AppGlass.buttonSize,
                    ),
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.titleSm.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right:
                        AppGrouped.margin -
                        (AppGlass.buttonSize - _closeSize) / 2,
                    child: _CloseButton(size: _closeSize),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppGrouped.margin,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...children,
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 實心圓形關閉鈕；面板本身不透明，不需要再疊一層玻璃模糊。
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '關閉',
      child: Semantics(
        button: true,
        label: '關閉',
        excludeSemantics: true,
        child: PressScale(
          onTap: () => Navigator.maybePop(context),
          child: SizedBox.square(
            // 觸控範圍維持 44，視覺圓鈕較小。
            dimension: AppGlass.buttonSize,
            child: Center(
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
