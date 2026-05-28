import 'package:flutter/material.dart';

class ReplaceEditForm extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController groupCtrl;
  final TextEditingController timeoutCtrl;
  final TextEditingController patternCtrl;
  final TextEditingController replacementCtrl;

  const ReplaceEditForm({
    super.key,
    required this.nameCtrl,
    required this.groupCtrl,
    required this.timeoutCtrl,
    required this.patternCtrl,
    required this.replacementCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: '規則名稱 *',
            border: OutlineInputBorder(),
          ),
          validator: (v) => v!.trim().isEmpty ? '名稱不能為空' : null,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: groupCtrl,
                decoration: const InputDecoration(
                  labelText: '分組',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: timeoutCtrl,
                decoration: const InputDecoration(
                  labelText: '超時 (ms)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: patternCtrl,
          decoration: const InputDecoration(
            labelText: '替換正則內容 *',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          validator: (v) => v!.trim().isEmpty ? '正則內容不能為空' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: replacementCtrl,
          decoration: const InputDecoration(
            labelText: '替換為內容',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
      ],
    );
  }
}
