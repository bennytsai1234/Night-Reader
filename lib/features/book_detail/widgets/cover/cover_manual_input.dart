import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import '../../book_detail_provider.dart';

class CoverManualInput extends StatelessWidget {
  final TextEditingController urlController;
  final Function() onPickImage;

  const CoverManualInput({
    super.key,
    required this.urlController,
    required this.onPickImage,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xl),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: urlController,
              decoration: const InputDecoration(
                hintText: '輸入封面 URL',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              if (urlController.text.isNotEmpty) {
                context.read<BookDetailProvider>().updateCover(
                  urlController.text.trim(),
                );
                Navigator.pop(context);
              }
            },
            child: const Text('確定'),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.photo_library),
            onPressed: onPickImage,
            tooltip: '從相簿選取',
          ),
        ],
      ),
    );
  }
}
// AI_PORT: GAP-COVER-01 extracted from ChangeCoverSheet
