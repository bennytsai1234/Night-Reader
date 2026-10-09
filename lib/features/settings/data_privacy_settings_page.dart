import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/services/app_permission_service.dart';
import 'package:night_reader/core/services/webview_data_service.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

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
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '資料與隱私'),
      body: GroupedListView(
        children: [
          GroupedSection(
            header: 'Cookie / WebView',
            children: [
              GroupedRow(
                title: '清除全部 Cookie',
                destructive: true,
                showChevron: false,
                enabled: !_busy,
                onTap: () => _confirmAndRun(
                  title: '清除全部 Cookie',
                  message: '這會移除所有書源登入狀態與驗證 Cookie。',
                  successMessage: '已清除全部 Cookie',
                  action: () async {
                    await _dataService.clearAllCookies();
                  },
                ),
              ),
              GroupedRow(
                title: '清除 WebView localStorage',
                destructive: true,
                showChevron: false,
                enabled: !_busy,
                onTap: () => _confirmAndRun(
                  title: '清除 WebView localStorage',
                  message: '這可能會讓部分需要網頁驗證的書源重新登入。',
                  successMessage: '已清除 WebView localStorage',
                  action: _dataService.clearWebViewLocalStorage,
                ),
              ),
              GroupedRow(
                title: '清除 WebView cache',
                destructive: true,
                showChevron: false,
                enabled: !_busy,
                onTap: () => _confirmAndRun(
                  title: '清除 WebView cache',
                  message: '這只會清除 WebView 快取，不會刪除書籍資料。',
                  successMessage: '已清除 WebView cache',
                  action: _dataService.clearWebViewCache,
                ),
              ),
            ],
          ),
          _buildPermissionSection(),
          GroupedSection(
            header: '說明',
            children: [
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.privacy_tip_outlined,
                  tint: AppTint.ink,
                ),
                title: '隱私說明',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PrivacyNoticePage()),
                ),
              ),
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.admin_panel_settings_outlined,
                  tint: AppTint.ink,
                ),
                title: '權限說明',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PermissionNoticePage(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required String successMessage,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: title,
      message: message,
      confirmLabel: '清除',
      destructive: true,
    );
    if (!confirmed) return;
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失敗: $error')));
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
          return const GroupedSection(
            header: '權限狀態',
            children: [
              GroupedContent(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          );
        }
        if (snapshot.hasError) {
          return GroupedSection(
            header: '權限狀態',
            children: [
              GroupedRow(
                title: '權限狀態載入失敗',
                subtitle: snapshot.error.toString(),
                maxSubtitleLines: 4,
                value: '重試',
                showChevron: false,
                onTap: _refreshPermissionSnapshot,
              ),
            ],
          );
        }

        final items = snapshot.data?.items ?? const <AppPermissionItem>[];
        return GroupedSection(
          header: '權限狀態',
          children: [
            for (final item in items) _permissionRow(item),
            GroupedRow(
              title: '開啟系統設定',
              accent: true,
              showChevron: false,
              onTap: () async {
                await _permissionService.openSystemSettings();
                _refreshPermissionSnapshot();
              },
            ),
            GroupedRow(
              title: '重新整理',
              accent: true,
              showChevron: false,
              onTap: _refreshPermissionSnapshot,
            ),
          ],
        );
      },
    );
  }

  Widget _permissionRow(AppPermissionItem item) {
    final color = _permissionColor(item.tone);
    return GroupedRow(
      // 與圖示方塊同寬，分隔線才會對齊文字起點。
      leading: SizedBox(
        width: AppGrouped.iconTile,
        child: Icon(_permissionIcon(item.tone), color: color, size: 24),
      ),
      title: item.title,
      showChevron: item.actionLabel != null,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 112),
        child: Text(
          item.status,
          textAlign: TextAlign.end,
          style: AppTextStyles.uiSm.copyWith(
            height: 1.3,
            color: color,
            fontWeight: FontWeight.w600,
          ),
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
        return AppChrome.of(context).sectionText;
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
          body: '書架、書源、章節、正文快取、閱讀進度、閱讀設定、替換規則與 TTS 設定會保存在本機資料庫或本機偏好設定中。',
        ),
        _NoticeSection(
          title: 'Cookie 與 WebView',
          body: '需要登入或驗證的書源可能會保存 Cookie。WebView 書源可能會產生 Cookie、localStorage 與網頁快取，可在資料與隱私頁清除。',
        ),
        _NoticeSection(
          title: '網路請求',
          body: '搜尋、詳情、目錄、正文、封面與書源驗證會向使用者配置的書源或網址發出請求，請求可能包含 User-Agent、Headers 與 Cookie。',
        ),
        _NoticeSection(
          title: '備份資料',
          body: '備份檔會包含書架、書源、閱讀進度、設定、規則與已快取正文等資料。備份檔目前不加密，請自行保存於可信位置。',
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
          body: '匯入本地書、匯入/匯出書源、備份與還原會透過系統檔案選擇器或分享面板讀取、建立檔案。App 只處理使用者選取或分享的檔案，不要求 Android 所有檔案存取權。',
        ),
        _NoticeSection(
          title: '網路',
          body: '網路權限用於搜尋書籍、載入章節、下載封面、同步 Cookie、WebView 驗證與書源調試。',
        ),
        _NoticeSection(
          title: '通知與背景任務',
          body: 'TTS 朗讀的媒體控制會使用通知權限；若使用者拒絕，朗讀仍可執行，但通知列控制可能無法顯示。背景任務會受到系統省電與背景執行設定限制。',
        ),
        _NoticeSection(
          title: '相簿',
          body: '更換書籍封面時可能會開啟系統圖片選取器。iOS 會顯示相簿權限提示，Android 以系統圖片選取流程為主，不要求整個相簿或儲存空間存取權。',
        ),
        _NoticeSection(
          title: 'WebView',
          body: '部分書源會使用 WebView 載入網頁、執行必要腳本或完成驗證。WebView 可能產生 Cookie、localStorage 與 cache。',
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassNavHeader(title: title),
      body: GroupedListView(
        children: [
          for (final section in sections)
            GroupedSection(
              header: section.title,
              children: [
                GroupedContent(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppGrouped.rowPadding,
                    vertical: AppSpacing.lg,
                  ),
                  child: Text(
                    section.body,
                    style: AppTextStyles.bodyBase.copyWith(
                      height: 1.55,
                      color: onSurface,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _NoticeSection {
  const _NoticeSection({required this.title, required this.body});

  final String title;
  final String body;
}
