import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_palette.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';

/// 閱讀器內設定面板的唯一開啟入口。
///
/// 面板配色跟隨閱讀選單主題（而非 App 主題），並在面板開啟期間
/// 隨選單主題變更即時更新。
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
      builder: (sheetContext) => ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final menuTheme = settings.currentMenuTheme;
          final theme = ReaderV2MenuStyle.resolve(
            context: context,
            backgroundColor: menuTheme.backgroundColor,
            textColor: menuTheme.textColor,
          ).toSheetTheme(Theme.of(context));
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
