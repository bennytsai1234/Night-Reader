import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'source_manager_provider.dart';

class SourceGroupManagePage extends StatelessWidget {
  const SourceGroupManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('書源分組管理'),
        actions: [
          Consumer<SourceManagerProvider>(
            builder:
                (context, provider, _) => IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '新增分組',
                  onPressed:
                      provider.isMutationBusy
                          ? null
                          : () => _showEditDialog(context),
                ),
          ),
        ],
      ),
      body: Consumer<SourceManagerProvider>(
        builder: (context, provider, child) {
          final groups = provider.allGroups;
          final mutationEnabled = !provider.isMutationBusy;

          if (groups.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 52,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    const Text('尚未建立自訂分組'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed:
                          mutationEnabled ? () => _showEditDialog(context) : null,
                      icon: const Icon(Icons.add),
                      label: const Text('新增分組'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: groups.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final group = groups[index];
              return ListTile(
                title: Text(group),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.share_outlined, size: 20),
                      tooltip: '分享此分組書源',
                      onPressed:
                          mutationEnabled
                              ? () => _shareGroup(context, provider, group)
                              : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: '重新命名分組',
                      onPressed:
                          mutationEnabled
                              ? () => _showEditDialog(context, oldName: group)
                              : null,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                        size: 20,
                      ),
                      tooltip: '刪除分組',
                      onPressed:
                          mutationEnabled
                              ? () => _confirmDelete(context, provider, group)
                              : null,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _shareGroup(
    BuildContext context,
    SourceManagerProvider p,
    String groupName,
  ) async {
    final urls = p.sourceUrlsInGroup(groupName);

    if (urls.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('該分組下無書源')));
      return;
    }

    try {
      await p.shareSourcesByUrls(urls, fileName: '$groupName.legado');
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('分享分組失敗：$error')));
      }
    }
  }

  Future<void> _showEditDialog(BuildContext context, {String? oldName}) async {
    final controller = TextEditingController(text: oldName);
    final provider = context.read<SourceManagerProvider>();
    final pageContext = context;
    String? inputError;
    try {
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => StatefulBuilder(
              builder:
                  (context, setDialogState) => AlertDialog(
                    title: Text(oldName == null ? '新增分組' : '重新命名分組'),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: '輸入分組名稱',
                        errorText: inputError,
                      ),
                      onChanged: (_) {
                        if (inputError != null) {
                          setDialogState(() => inputError = null);
                        }
                      },
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('取消'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          final name = controller.text.trim();
                          if (name.isEmpty) {
                            setDialogState(() => inputError = '請輸入分組名稱');
                            return;
                          }
                          Navigator.pop(dialogContext);
                          try {
                            if (oldName == null) {
                              await provider.addGroup(name);
                            } else {
                              await provider.renameGroup(oldName, name);
                            }
                          } catch (error) {
                            if (pageContext.mounted) {
                              ScaffoldMessenger.of(pageContext).showSnackBar(
                                SnackBar(content: Text('儲存分組失敗：$error')),
                              );
                            }
                          }
                        },
                        child: const Text('確定'),
                      ),
                    ],
                  ),
            ),
      );
    } finally {
      controller.dispose();
    }
  }

  void _confirmDelete(
    BuildContext context,
    SourceManagerProvider provider,
    String name,
  ) {
    final pageContext = context;
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('刪除分組'),
            content: Text('確定要刪除分組 "$name" 嗎？\n這不會刪除書源，只會移除該分組標籤。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    await provider.deleteGroup(name);
                  } catch (error) {
                    if (pageContext.mounted) {
                      ScaffoldMessenger.of(
                        pageContext,
                      ).showSnackBar(SnackBar(content: Text('刪除分組失敗：$error')));
                    }
                  }
                },
                child: Text(
                  '刪除',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
    );
  }
}
