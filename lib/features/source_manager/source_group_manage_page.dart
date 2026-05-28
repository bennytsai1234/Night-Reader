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
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showEditDialog(context),
          ),
        ],
      ),
      body: Consumer<SourceManagerProvider>(
        builder: (context, provider, child) {
          // 使用 provider.allGroups (已排序且排除 '全部')
          final groups = provider.allGroups;

          if (groups.isEmpty) {
            return const Center(child: Text('暫無自訂分組'));
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
                      onPressed: () => _shareGroup(context, provider, group),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _showEditDialog(context, oldName: group),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                        size: 20,
                      ),
                      onPressed: () => _confirmDelete(context, provider, group),
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
    // 1. 篩選該分組書源
    final urls =
        p.sources
            .where((s) => s.bookSourceGroup?.contains(groupName) ?? false)
            .map((s) => s.bookSourceUrl)
            .toSet();

    if (urls.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('該分組下無書源')));
      return;
    }

    // 2. 調用 Provider 實作的分享邏輯 (重用 batch share 邏輯)
    // 這裡我們需要一個能接收特定 URL 集合的分享方法
    await p.shareSourcesByUrls(urls, fileName: '$groupName.legado');
  }

  void _showEditDialog(BuildContext context, {String? oldName}) {
    final controller = TextEditingController(text: oldName);
    final provider = context.read<SourceManagerProvider>();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(oldName == null ? '新增分組' : '重新命名分組'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '輸入分組名稱'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isNotEmpty) {
                    if (oldName == null) {
                      provider.addGroup(name);
                    } else {
                      provider.renameGroup(oldName, name);
                    }
                    Navigator.pop(context);
                  }
                },
                child: const Text('確定'),
              ),
            ],
          ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    SourceManagerProvider provider,
    String name,
  ) {
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
                onPressed: () {
                  provider.deleteGroup(name);
                  Navigator.pop(context);
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
