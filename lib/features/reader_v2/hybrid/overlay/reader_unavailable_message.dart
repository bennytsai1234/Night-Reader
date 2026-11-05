import 'package:flutter/material.dart';

import 'package:night_reader/shared/theme/app_text_styles.dart';

/// 正文取不到、閱讀器沒有東西可畫時，紙中間的提示。
final class ReaderUnavailableMessage extends StatelessWidget {
  const ReaderUnavailableMessage({
    super.key,
    required this.message,
    required this.textColor,
  });

  final String message;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: textColor.withValues(alpha: 0.72),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: AppTextStyles.bodyBase.copyWith(color: textColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
