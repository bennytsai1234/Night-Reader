import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/reader_v2_replace_rule_editor_sheet.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';

class ReaderV2ReplaceRulePage extends StatefulWidget {
  const ReaderV2ReplaceRulePage({super.key});

  @override
  State<ReaderV2ReplaceRulePage> createState() =>
      _ReaderV2ReplaceRulePageState();
}

class _ReaderV2ReplaceRulePageState extends State<ReaderV2ReplaceRulePage> {
  final ReplaceRuleDao _replaceDao = getIt<ReplaceRuleDao>();
  bool _loading = true;
  Object? _loadError;
  List<ReplaceRule> _rules = const <ReplaceRule>[];

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rules = await _replaceDao.getAll();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
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
    if (mounted) await _loadRules();
  }

  Future<void> _deleteRule(ReplaceRule rule) async {
    try {
      await _replaceDao.deleteById(rule.id);
      await _loadRules();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('刪除規則失敗：$error')));
    }
  }

  Future<void> _toggleEnabled(ReplaceRule rule, bool enabled) async {
    try {
      await _replaceDao.updateEnabled(rule.id, enabled);
      await _loadRules();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新規則狀態失敗：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('替換規則'),
        actions: [
          IconButton(
            onPressed: _loading || _loadError != null ? null : () => _openEditor(),
            icon: const Icon(Icons.add),
            tooltip: '新增規則',
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
              ? AppStateView(
                icon: Icons.error_outline,
                title: '替換規則載入失敗',
                description: '無法讀取現有規則，請稍後再試。',
                tone: AppStateTone.error,
                primaryAction: AppStateAction(
                  label: '重試',
                  icon: Icons.refresh,
                  onPressed: _loadRules,
                ),
              )
              : _rules.isEmpty
              ? AppStateView(
                icon: Icons.rule_rounded,
                title: '還沒有替換規則',
                description: '新增規則後，可在閱讀時自動整理標題或正文。',
                primaryAction: AppStateAction(
                  label: '新增規則',
                  icon: Icons.add,
                  onPressed: _openEditor,
                ),
              )
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
                          '${rule.pattern} → ${rule.replacement}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _chip(context, rule.isEnabled ? '已啟用' : '已停用'),
                            _chip(context, rule.isRegex ? '正則' : '純文字'),
                            if (rule.scopeContent) _chip(context, '正文'),
                            if (rule.scopeTitle) _chip(context, '標題'),
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

  Widget _chip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
