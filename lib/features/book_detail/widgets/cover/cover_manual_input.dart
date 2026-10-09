import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

import '../../book_detail_provider.dart';

/// 換封面面板底部：手動輸入網址（分組輸入列）＋「確定」與從相簿選取。
class CoverManualInput extends StatelessWidget {
  final TextEditingController urlController;
  final Future<void> Function() onPickImage;

  const CoverManualInput({
    super.key,
    required this.urlController,
    required this.onPickImage,
  });

  Future<void> _submit(BuildContext context) async {
    final url = urlController.text.trim();
    if (url.isEmpty) return;
    final outcome = await context.read<BookDetailProvider>().updateCover(url);
    if (!context.mounted) return;
    if (outcome.success) {
      Navigator.pop(context);
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(outcome.message)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppGrouped.margin,
        AppSpacing.md,
        AppGrouped.margin,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: AppGrouped.cardRadius,
              child: ColoredBox(
                color: AppChrome.of(context).groupedSurface,
                child: GroupedTextFieldRow(
                  controller: urlController,
                  hintText: '輸入封面 URL',
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(context),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          GlassTextButton(
            label: '確定',
            emphasized: true,
            onPressed: () => _submit(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          GlassIconButton(
            icon: Icons.photo_library_outlined,
            iconSize: 20,
            onPressed: onPickImage,
            tooltip: '從相簿選取',
          ),
        ],
      ),
    );
  }
}
// AI_PORT: GAP-COVER-01 extracted from ChangeCoverSheet
