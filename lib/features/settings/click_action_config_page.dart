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
  List<int> _actions = ReaderV2TapAction.defaultGrid();

  @override
  void initState() {
    super.initState();
    _loadActions();
  }

  Future<void> _loadActions() async {
    final snapshot = await _prefsRepository.load();
    if (!mounted) return;
    setState(() {
      _actions = snapshot.clickActions;
      _isLoading = false;
    });
  }

  Future<void> _saveActions() async {
    await _prefsRepository.saveClickActions(_actions);
  }

  Future<void> _resetActions() async {
    setState(() {
      _actions = ReaderV2TapAction.defaultGrid();
    });
    await _saveActions();
  }

  Future<void> _updateAction(int index, int action) async {
    setState(() {
      _actions[index] = action;
    });
    await _saveActions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('點擊區域設置'),
        actions: [
          TextButton(
            onPressed: () => _resetActions(),
            child: const Text('恢復預設', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      '預設為九宮格全部喚起選單，可逐格改成翻頁、換章、朗讀或書籤。',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.6,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                        itemCount: 9,
                        itemBuilder: (ctx, index) {
                          return InkWell(
                            onTap: () => _showActionSelector(context, index),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.5),
                                ),
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.05),
                                borderRadius: AppRadius.cardSm,
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '區域 ${index + 1}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      ReaderV2TapAction.fromCode(
                                        _actions[index],
                                      ).label,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
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
                ],
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
