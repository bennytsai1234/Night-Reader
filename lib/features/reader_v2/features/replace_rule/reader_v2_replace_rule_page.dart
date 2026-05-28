import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/reader_v2_replace_rule_editor_sheet.dart';

class ReaderV2ReplaceRulePage extends StatefulWidget {
  const ReaderV2ReplaceRulePage({super.key});

  @override
  State<ReaderV2ReplaceRulePage> createState() =>
      _ReaderV2ReplaceRulePageState();
}

class _ReaderV2ReplaceRulePageState extends State<ReaderV2ReplaceRulePage> {
  final ReplaceRuleDao _replaceDao = getIt<ReplaceRuleDao>();
  bool _loading = true;
  List<ReplaceRule> _rules = const <ReplaceRule>[];

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() {
      _loading = true;
    });
    final rules = await _replaceDao.getAll();
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _loading = false;
    });
  }

  Future<void> _openEditor({ReplaceRule? rule}) async {
    await ReaderV2ReplaceRuleEditorSheet.show(
      context,
      rule: rule,
      onSave: (next) async {
        if (next.id == 0) {
          next.order = _rules.length;
        }
        await _replaceDao.upsert(next);
      },
    );
    await _loadRules();
  }

  Future<void> _deleteRule(ReplaceRule rule) async {
    await _replaceDao.deleteById(rule.id);
    await _loadRules();
  }

  Future<void> _toggleEnabled(ReplaceRule rule, bool enabled) async {
    await _replaceDao.updateEnabled(rule.id, enabled);
    await _loadRules();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('替換規則'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _openEditor(),
            icon: const Icon(Icons.add),
            tooltip: '新增規則',
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _rules.isEmpty
              ? _buildEmptyState(context)
              : ListView.separated(
                itemCount: _rules.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final rule = _rules[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    title: Text(
                      rule.name.isEmpty ? '未命名規則' : rule.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          '${rule.pattern} -> ${rule.replacement}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _chip(rule.isEnabled ? '已啟用' : '已停用'),
                            _chip(rule.isRegex ? '正則' : '純文字'),
                            if (rule.scopeContent) _chip('正文'),
                            if (rule.scopeTitle) _chip('標題'),
                          ],
                        ),
                      ],
                    ),
                    onTap: () => _openEditor(rule: rule),
                    trailing: SizedBox(
                      width: 104,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Switch(
                            value: rule.isEnabled,
                            onChanged: (value) => _toggleEnabled(rule, value),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: '刪除',
                            onPressed: () => _confirmDelete(rule),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.rule_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text('還沒有替換規則'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('新增規則'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  Future<void> _confirmDelete(ReplaceRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('刪除規則'),
            content: Text(
              '確定刪除「${rule.name.isEmpty ? rule.pattern : rule.name}」？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('刪除'),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      await _deleteRule(rule);
    }
  }
}
