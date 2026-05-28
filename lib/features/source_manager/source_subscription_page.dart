import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:reader/shared/theme/app_text_styles.dart';
import 'package:reader/core/models/source_subscription.dart';
import 'package:reader/core/database/dao/source_subscription_dao.dart';
import 'package:reader/core/services/source_update_service.dart';
import 'package:reader/core/di/injection.dart';

class SourceSubscriptionProvider extends ChangeNotifier {
  final SourceSubscriptionDao _dao = getIt<SourceSubscriptionDao>();
  final SourceUpdateService _updateService = SourceUpdateService();

  List<SourceSubscription> _subs = [];
  List<SourceSubscription> get subs => _subs;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  SourceSubscriptionProvider() {
    loadSubs();
  }

  Future<void> loadSubs() async {
    _isLoading = true;
    notifyListeners();
    _subs = await _dao.getAll();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addSub(String name, String url) async {
    final sub = SourceSubscription(name: name, url: url);
    await _dao.upsert(sub);
    await loadSubs();
  }

  Future<void> updateSub(SourceSubscription sub) async {
    await _dao.upsert(sub);
    await loadSubs();
  }

  Future<void> deleteSub(SourceSubscription sub) async {
    await _dao.deleteByUrl(sub.url);
    await loadSubs();
  }

  Future<void> syncAll() async {
    _isLoading = true;
    notifyListeners();
    for (var sub in _subs) {
      await _updateService.updateFromSubscription(sub);
    }
    await loadSubs();
  }

  Future<void> syncOne(SourceSubscription sub) async {
    await _updateService.updateFromSubscription(sub);
    await loadSubs();
  }
}

class SourceSubscriptionPage extends StatelessWidget {
  const SourceSubscriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SourceSubscriptionProvider(),
      child: const _SubscriptionListContent(),
    );
  }
}

class _SubscriptionListContent extends StatelessWidget {
  const _SubscriptionListContent();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SourceSubscriptionProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('書源訂閱'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: '全部更新',
            onPressed: provider.isLoading ? null : () => provider.syncAll(),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showEditDialog(context, provider),
          ),
        ],
      ),
      body:
          provider.isLoading && provider.subs.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : provider.subs.isEmpty
              ? const Center(child: Text('暫無訂閱位址'))
              : ListView.separated(
                itemCount: provider.subs.length,
                separatorBuilder: (ctx, i) => const Divider(height: 1),
                itemBuilder:
                    (ctx, i) =>
                        _buildSubItem(context, provider, provider.subs[i]),
              ),
    );
  }

  Widget _buildSubItem(
    BuildContext context,
    SourceSubscriptionProvider p,
    SourceSubscription sub,
  ) {
    final lastUpdate =
        sub.lastUpdateTime > 0
            ? DateFormat(
              'yyyy-MM-dd HH:mm',
            ).format(DateTime.fromMillisecondsSinceEpoch(sub.lastUpdateTime))
            : '從未更新';

    return ListTile(
      title: Text(
        sub.name,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sub.url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSm,
          ),
          Text(
            '最後更新: $lastUpdate',
            style: AppTextStyles.labelXs.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => p.syncOne(sub),
          ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'edit') _showEditDialog(context, p, sub: sub);
              if (val == 'delete') p.deleteSub(sub);
            },
            itemBuilder:
                (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('編輯')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      '刪除',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    SourceSubscriptionProvider p, {
    SourceSubscription? sub,
  }) {
    final nameCtrl = TextEditingController(text: sub?.name ?? '');
    final urlCtrl = TextEditingController(text: sub?.url ?? '');

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(sub == null ? '新增訂閱' : '編輯訂閱'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '名稱',
                    hintText: '例如：一程書源',
                  ),
                ),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(labelText: '訂閱網址'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (sub == null) {
                    p.addSub(nameCtrl.text, urlCtrl.text);
                  } else {
                    sub.name = nameCtrl.text;
                    sub.url = urlCtrl.text;
                    p.updateSub(sub);
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('儲存'),
              ),
            ],
          ),
    );
  }
}
