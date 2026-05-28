import 'package:flutter/material.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import 'package:reader/shared/theme/app_text_styles.dart';
import 'package:reader/core/services/app_permission_service.dart';
import 'package:reader/core/services/webview_data_service.dart';
import 'package:reader/shared/theme/context_ext.dart';

class DataPrivacySettingsPage extends StatefulWidget {
  const DataPrivacySettingsPage({super.key});

  @override
  State<DataPrivacySettingsPage> createState() =>
      _DataPrivacySettingsPageState();
}

class _DataPrivacySettingsPageState extends State<DataPrivacySettingsPage> {
  final WebViewDataService _dataService = WebViewDataService();
  final AppPermissionService _permissionService = AppPermissionService();
  late Future<AppPermissionSnapshot> _permissionSnapshot;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _permissionSnapshot = _permissionService.loadSnapshot();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('資料與隱私')),
      body: ListView(
        children: [
          _sectionTitle('Cookie / WebView'),
          ListTile(
            leading: const Icon(Icons.cookie_outlined),
            title: const Text('清除全部 Cookie'),
            subtitle: const Text('清除 App Cookie、網路請求 Cookie 與 WebView Cookie'),
            enabled: !_busy,
            onTap:
                () => _confirmAndRun(
                  title: '清除全部 Cookie',
                  message: '這會移除所有書源登入狀態與驗證 Cookie。',
                  successMessage: '已清除全部 Cookie',
                  action: () async {
                    await _dataService.clearAllCookies();
                  },
                ),
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('清除 WebView localStorage'),
            subtitle: const Text('移除網頁儲存的本機資料'),
            enabled: !_busy,
            onTap:
                () => _confirmAndRun(
                  title: '清除 WebView localStorage',
                  message: '這可能會讓部分需要網頁驗證的書源重新登入。',
                  successMessage: '已清除 WebView localStorage',
                  action: _dataService.clearWebViewLocalStorage,
                ),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('清除 WebView cache'),
            subtitle: const Text('清除 WebView 的網頁快取資料'),
            enabled: !_busy,
            onTap:
                () => _confirmAndRun(
                  title: '清除 WebView cache',
                  message: '這只會清除 WebView 快取，不會刪除書籍資料。',
                  successMessage: '已清除 WebView cache',
                  action: _dataService.clearWebViewCache,
                ),
          ),
          const Divider(),
          _sectionTitle('權限狀態'),
          _buildPermissionSection(),
          const Divider(),
          _sectionTitle('說明'),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('隱私說明'),
            subtitle: const Text('本地資料、Cookie、WebView、備份與網路請求'),
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PrivacyNoticePage()),
                ),
          ),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text('權限說明'),
            subtitle: const Text('檔案、通知、背景任務與網路相關權限'),
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PermissionNoticePage(),
                  ),
                ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        style: AppTextStyles.bodyXs.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required String successMessage,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('清除'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await _run(successMessage: successMessage, action: action);
  }

  Future<void> _run({
    required String successMessage,
    required Future<void> Function() action,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('操作失敗: $error')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _buildPermissionSection() {
    return FutureBuilder<AppPermissionSnapshot>(
      future: _permissionSnapshot,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('權限狀態載入失敗'),
            subtitle: Text(snapshot.error.toString()),
            trailing: IconButton(
              tooltip: '重試',
              icon: const Icon(Icons.refresh),
              onPressed: _refreshPermissionSnapshot,
            ),
          );
        }

        final items = snapshot.data?.items ?? const <AppPermissionItem>[];
        return Column(
          children: [
            for (final item in items) _permissionTile(item),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _permissionService.openSystemSettings();
                      _refreshPermissionSnapshot();
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('系統設定'),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _refreshPermissionSnapshot,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新整理'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _permissionTile(AppPermissionItem item) {
    final color = _permissionColor(item.tone);
    return ListTile(
      leading: Icon(_permissionIcon(item.tone), color: color),
      title: Text(item.title),
      subtitle: Text(item.description),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 112),
        child: Text(
          item.status,
          textAlign: TextAlign.end,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
      onTap: item.actionLabel == null ? null : () => _handlePermissionTap(item),
    );
  }

  Future<void> _handlePermissionTap(AppPermissionItem item) async {
    if (item.title == '通知') {
      await _permissionService.requestNotificationForTts();
    } else if (item.title == '相簿') {
      await _permissionService.requestPhotoLibraryIfNeeded();
    }
    _refreshPermissionSnapshot();
  }

  void _refreshPermissionSnapshot() {
    if (!mounted) return;
    setState(() {
      _permissionSnapshot = _permissionService.loadSnapshot();
    });
  }

  IconData _permissionIcon(AppPermissionStatusTone tone) {
    switch (tone) {
      case AppPermissionStatusTone.ok:
        return Icons.check_circle_outline;
      case AppPermissionStatusTone.attention:
        return Icons.info_outline;
      case AppPermissionStatusTone.blocked:
        return Icons.block;
      case AppPermissionStatusTone.neutral:
        return Icons.radio_button_unchecked;
    }
  }

  Color _permissionColor(AppPermissionStatusTone tone) {
    final scheme = Theme.of(context).colorScheme;
    switch (tone) {
      case AppPermissionStatusTone.ok:
        return context.success;
      case AppPermissionStatusTone.attention:
        return scheme.primary;
      case AppPermissionStatusTone.blocked:
        return scheme.error;
      case AppPermissionStatusTone.neutral:
        return scheme.onSurfaceVariant;
    }
  }
}

class PrivacyNoticePage extends StatelessWidget {
  const PrivacyNoticePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _NoticePage(
      title: '隱私說明',
      sections: [
        _NoticeSection(
          title: '本地資料',
          body: '書架、書源、章節、正文快取、書籤、閱讀進度、閱讀設定、替換規則與 TTS 設定會保存在本機資料庫或本機偏好設定中。',
        ),
        _NoticeSection(
          title: 'Cookie 與 WebView',
          body:
              '需要登入或驗證的書源可能會保存 Cookie。WebView 書源可能會產生 Cookie、localStorage 與網頁快取，可在資料與隱私頁清除。',
        ),
        _NoticeSection(
          title: '網路請求',
          body:
              '搜尋、詳情、目錄、正文、封面與書源驗證會向使用者配置的書源或網址發出請求，請求可能包含 User-Agent、Headers 與 Cookie。',
        ),
        _NoticeSection(
          title: '備份資料',
          body: '備份檔會包含書架、書源、書籤、閱讀進度、設定、規則與已快取正文等資料。備份檔目前不加密，請自行保存於可信位置。',
        ),
        _NoticeSection(
          title: 'Crash log',
          body: 'Crash log 用於除錯，可能包含錯誤訊息、網址或書源解析資訊。App 不會自動上傳這些 log。',
        ),
      ],
    );
  }
}

class PermissionNoticePage extends StatelessWidget {
  const PermissionNoticePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _NoticePage(
      title: '權限說明',
      sections: [
        _NoticeSection(
          title: '檔案',
          body:
              '匯入本地書、匯入/匯出書源、備份與還原會透過系統檔案選擇器或分享面板讀取、建立檔案。App 只處理使用者選取或分享的檔案，不要求 Android 所有檔案存取權。',
        ),
        _NoticeSection(
          title: '網路',
          body: '網路權限用於搜尋書籍、載入章節、下載封面、同步 Cookie、WebView 驗證與書源調試。',
        ),
        _NoticeSection(
          title: '通知與背景任務',
          body:
              'TTS 朗讀的媒體控制會使用通知權限；若使用者拒絕，朗讀仍可執行，但通知列控制可能無法顯示。背景任務會受到系統省電與背景執行設定限制。',
        ),
        _NoticeSection(
          title: '相簿',
          body:
              '更換書籍封面時可能會開啟系統圖片選取器。iOS 會顯示相簿權限提示，Android 以系統圖片選取流程為主，不要求整個相簿或儲存空間存取權。',
        ),
        _NoticeSection(
          title: 'WebView',
          body:
              '部分書源會使用 WebView 載入網頁、執行必要腳本或完成驗證。WebView 可能產生 Cookie、localStorage 與 cache。',
        ),
      ],
    );
  }
}

class _NoticePage extends StatelessWidget {
  const _NoticePage({required this.title, required this.sections});

  final String title;
  final List<_NoticeSection> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        itemBuilder: (context, index) {
          final section = sections[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(section.body, style: Theme.of(context).textTheme.bodyMedium),
            ],
          );
        },
        separatorBuilder: (_, _) => const SizedBox(height: 20),
        itemCount: sections.length,
      ),
    );
  }
}

class _NoticeSection {
  const _NoticeSection({required this.title, required this.body});

  final String title;
  final String body;
}
