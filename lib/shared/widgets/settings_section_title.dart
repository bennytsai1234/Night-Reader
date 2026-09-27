import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 設定頁的區塊標題；所有設定頁共用同一字級、色彩與間距。
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(
    this.title, {
    super.key,
    this.horizontalPadding = AppSpacing.md,
  });

  final String title;

  /// 與同頁列表內容的水平邊距對齊。
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        AppSpacing.xl,
        horizontalPadding,
        AppSpacing.sm,
      ),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: AppTextStyles.bodySm.copyWith(
            height: 1.3,
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
