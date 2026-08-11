import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_tap_action.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';

class ClickActionConfigPage extends StatefulWidget {
  const ClickActionConfigPage({super.key});

  @override
  State<ClickActionConfigPage> createState() => _ClickActionConfigPageState();
}

class _ClickActionConfigPageState extends State<ClickActionConfigPage> {
  final ReaderV2PrefsRepository _prefsRepository =
      const ReaderV2PrefsRepository();

  bool _isLoading = true;
  bool _isSaving = false;
  Object? _loadError;
  List<int> _actions = ReaderV2TapAction.defaultGrid();

  @override
  void initState() {
    super.initState();
    _loadActions();
  }

  Future<void> _loadActions() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final snapshot = await _prefsRepository.load();
      if (!mounted) return;
      setState(() {
        _actions = List<int>.from(snapshot.clickActions);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error;
      });
    }
  }

  Future<void> _resetActions() async {
    if (_isSaving) return;
    final previous = List<int>.from(_actions);
    final next = ReaderV2TapAction.defaultGrid();
    setState(() {
      _actions = next;
      _isSaving = true;
    });
    try {
      await _prefsRepository.saveClickActions(next);
      if (!mounted) return;
      _showMessage('已恢復預設設定');
    } catch (error) {
      if (!mounted) return;
      setState(() => _actions = previous);
      _showMessage('恢復預設失敗：$error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _updateAction(int index, int action) async {
    if (_isSaving || index < 0 || index >= _actions.length) return;
    final previous = _actions[index];
    final next = List<int>.from(_actions)..[index] = action;
    setState(() {
      _actions = next;
      _isSaving = true;
    });
    try {
      await _prefsRepository.saveClickActions(next);
      if (!mounted) return;
      _showMessage('已儲存點擊區域設定');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        final rolledBack = List<int>.from(_actions);
        rolledBack[index] = previous;
        _actions = rolledBack;
      });
      _showMessage('儲存點擊區域設定失敗：$error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('點擊區域設定'),
        actions: [
          TextButton(
            onPressed:
                _isLoading || _loadError != null || _isSaving
                    ? null
                    : _resetActions,
            child: const Text('恢復預設'),
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
              ? _buildLoadError(context)
              : Column(
                children: [
                  if (_isSaving) const LinearProgressIndicator(minHeight: 2),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.md,
                    ),
                    child: Text(
                      '預設為九宮格全部喚起選單，可逐格改成翻頁、換章、朗讀或書籤。',
                      style: TextStyle(
                        height: 1.45,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: IgnorePointer(
                      ignoring: _isSaving,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          AppSpacing.md,
                          AppSpacing.xl,
                          AppSpacing.xxl,
                        ),
                        child: GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 0.6,
                                crossAxisSpacing: AppSpacing.md,
                                mainAxisSpacing: AppSpacing.md,
                              ),
                          itemCount: 9,
                          itemBuilder: (ctx, index) {
                            return InkWell(
                              borderRadius: AppRadius.cardMd,
                              onTap: () => _showActionSelector(context, index),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.5),
                                  ),
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.05),
                                  borderRadius: AppRadius.cardMd,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '區域 ${index + 1}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.3,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.md),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.sm,
                                        ),
                                        child: Text(
                                          ReaderV2TapAction.fromCode(
                                            _actions[index],
                                          ).label,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _buildLoadError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('點擊區域設定載入失敗'),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _loadActions,
              icon: const Icon(Icons.refresh),
              label: const Text('重試'),
            ),
          ],
        ),
      ),
    );
  }

  void _showActionSelector(BuildContext context, int index) {
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.5,
              ),
              child: ListView(
                shrinkWrap: true,
                children:
                    ReaderV2TapAction.values.map((entry) {
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                        ),
                        title: Text(entry.label),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _updateAction(index, entry.code);
                        },
                      );
                    }).toList(),
              ),
            ),
          ),
    );
  }
}
