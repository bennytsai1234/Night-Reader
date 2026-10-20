import 'package:flutter/material.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/update_preferences.dart';
import 'package:night_reader/core/services/webview_data_service.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'crash_log_page.dart';
import 'external_url_launcher.dart';
import 'privacy_pages.dart';
import 'release_notes_page.dart';
import 'update_check_runner.dart';

/// 「自動更新」的三種：不自動檢查、自動檢查（有新版時問要不要下載）、自動
/// 檢查並在 Wi-Fi 下直接下載。
enum _AppUpdateMode {
  manual('不自動'),
  check('自動檢查'),
  download('Wi-Fi 下自動下載');

  const _AppUpdateMode(this.label);
  final String label;
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  // 載入前不顯示版號；讀不到時顯示「未知版本」，不會停在錯誤的預設值。
  String? _version;
  String _buildNumber = '';
  bool _checkingUpdate = false;
  final _updatePreferences = UpdatePreferences();
  bool _betaChannel = false;
  bool _autoCheck = true;
  bool _autoDownload = UpdatePreferences.defaultAutoDownload;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadUpdatePreferences();
  }

  Future<void> _loadUpdatePreferences() async {
    final betaChannel = await _updatePreferences.betaChannel();
    final autoCheck = await _updatePreferences.autoCheck();
    final autoDownload = await _updatePreferences.autoDownload();
    if (!mounted) return;
    setState(() {
      _betaChannel = betaChannel;
      _autoCheck = autoCheck;
      _autoDownload = autoDownload;
    });
  }

  Future<void> _setBetaChannel(bool enabled) async {
    setState(() => _betaChannel = enabled);
    await _updatePreferences.setBetaChannel(enabled);
  }

  _AppUpdateMode get _updateMode => !_autoCheck
      ? _AppUpdateMode.manual
      : _autoDownload
      ? _AppUpdateMode.download
      : _AppUpdateMode.check;

  /// 「自動檢查」與「在 Wi-Fi 下自動下載」原本是兩個開關，後者只在前者開著
  /// 時有作用；合成一列三選一。
  Future<void> _setUpdateMode(_AppUpdateMode mode) async {
    setState(() {
      _autoCheck = mode != _AppUpdateMode.manual;
      if (_autoCheck) _autoDownload = mode == _AppUpdateMode.download;
    });
    await _updatePreferences.setAutoCheck(_autoCheck);
    if (_autoCheck) await _updatePreferences.setAutoDownload(_autoDownload);
  }

  Future<void> _pickUpdateMode(BuildContext rowContext) async {
    final picked = await showGlassMenu<_AppUpdateMode>(
      context: rowContext,
      anchor: globalRectOf(rowContext),
      entries: [
        for (final mode in _AppUpdateMode.values)
          GlassMenuItem(
            value: mode,
            label: mode.label,
            checked: mode == _updateMode,
          ),
      ],
    );
    if (picked != null) await _setUpdateMode(picked);
  }

  bool _clearingWebData = false;

  /// 書源登入用的 Cookie、WebView 的 localStorage 與快取一起清掉。原本是三個
  /// 分開的按鈕，結果都是「需要網頁驗證的書源可能要重新驗證」。
  Future<void> _clearWebData() async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '清除網頁資料',
      message: '會清除書源的 Cookie、WebView 的 localStorage 與快取，需要登入或網頁驗證的書源要重新驗證；書籍與正文不受影響。',
      confirmLabel: '清除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _clearingWebData = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = WebViewDataService();
      await service.clearAllCookies();
      await service.clearWebViewLocalStorage();
      await service.clearWebViewCache();
      messenger.showSnackBar(const SnackBar(content: Text('已清除網頁資料')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage('清除網頁資料', error))),
      );
    } finally {
      if (mounted) setState(() => _clearingWebData = false);
    }
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    } catch (error, stackTrace) {
      AppLog.e('讀取版本資訊失敗', error: error, stackTrace: stackTrace);
      if (mounted) setState(() => _version = '');
    }
  }

  /// 頁面上顯示的版號：載入中為空字串，讀不到為「未知版本」。
  String get _versionLabel => switch (_version) {
    null => '',
    '' => '未知版本',
    final version => 'v$version',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '關於夜讀'),
      body: GroupedListView(
        children: [
          _buildAppLogo(context),
          GroupedSection(
            header: '開源與法律',
            children: [
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.code_rounded,
                  tint: AppTint.ink,
                ),
                title: 'GitHub 開源位址',
                subtitle: 'bennytsai1234/Night-Reader',
                onTap: () => launchExternalUrlWithFeedback(
                  context,
                  'https://github.com/bennytsai1234/Night-Reader',
                ),
              ),
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.description_outlined,
                  tint: AppTint.azurite,
                ),
                title: '開源許可證',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: '夜讀',
                  applicationVersion: _version == null || _version!.isEmpty
                      ? null
                      : '$_version ($_buildNumber)',
                ),
              ),
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.gavel_outlined,
                  tint: AppTint.gold,
                ),
                title: '免責聲明',
                onTap: () => _showDisclaimer(context),
              ),
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
                title: '權限',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PermissionsPage()),
                ),
              ),
            ],
          ),
          GroupedSection(
            header: '系統工具',
            children: [
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.system_update_alt_rounded,
                  tint: AppTint.moss,
                ),
                title: '檢查更新',
                // 目前版本寫在頁頂圖示下方，這裡只在檢查時顯示狀態。
                value: _checkingUpdate ? '檢查中…' : null,
                trailing: _checkingUpdate
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                showChevron: !_checkingUpdate,
                onTap: _checkUpdate,
              ),
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.history_rounded,
                  tint: AppTint.ink,
                ),
                title: '更新紀錄',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReleaseNotesPage()),
                ),
              ),
              Builder(
                builder: (rowContext) => GroupedRow(
                  leading: const GroupedIconTile(
                    Icons.update_rounded,
                    tint: AppTint.azurite,
                  ),
                  title: '自動更新',
                  value: _updateMode.label,
                  showChevron: false,
                  onTap: () => _pickUpdateMode(rowContext),
                ),
              ),
              GroupedSwitchRow(
                leading: const GroupedIconTile(
                  Icons.science_outlined,
                  tint: AppTint.aubergine,
                ),
                title: '接收測試版更新',
                value: _betaChannel,
                onChanged: _setBetaChannel,
              ),
              GroupedSwitchRow(
                leading: const GroupedIconTile(
                  Icons.auto_stories_outlined,
                  tint: AppTint.azurite,
                ),
                title: '啟動時檢查書架更新',
                value: context.select<SettingsProvider, bool>(
                  (settings) => settings.autoRefresh,
                ),
                onChanged: context.read<SettingsProvider>().setAutoRefresh,
              ),
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.cleaning_services_outlined,
                  tint: AppTint.tea,
                ),
                title: '清除網頁資料',
                showChevron: false,
                enabled: !_clearingWebData,
                onTap: _clearWebData,
              ),
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.report_problem_outlined,
                  tint: AppTint.rust,
                ),
                title: '崩潰日誌',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CrashLogPage()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppLogo(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: AppRadius.cardXl,
            child: Image.asset(
              'assets/ui/app_icon.webp',
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              semanticLabel: '夜讀應用程式圖示',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '夜讀',
            style: AppTextStyles.titleLg.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _versionLabel,
            style: AppTextStyles.bodySm.copyWith(
              height: 1.4,
              color: AppChrome.of(context).sectionText,
            ),
          ),
        ],
      ),
    );
  }

  void _showDisclaimer(BuildContext context) {
    showAppAlert<void>(
      context: context,
      title: '免責聲明',
      content: Text(
        '1. 本軟體僅作為開源閱讀工具使用，不提供任何書籍、書源或訂閱內容。\n\n'
        '2. 使用者應遵守當地法律法規，並對所導入的內容承擔全部法律責任。\n\n'
        '3. 對於使用本軟體產生的任何版權爭議、數據損失，開發者概不負責。',
        style: AppTextStyles.bodySm.copyWith(
          height: 1.55,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      actions: const [
        AppAlertAction(label: '我已閱讀並知曉', value: null, isDefault: true),
      ],
    );
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    final outcome = await UpdateCheckRunner().runManual(context);
    if (!mounted) return;
    setState(() => _checkingUpdate = false);
    final message = switch (outcome) {
      UpdateCheckOutcome.shown => null,
      UpdateCheckOutcome.upToDate => '已是最新版',
      UpdateCheckOutcome.failed => '檢查更新失敗，請稍後再試',
      UpdateCheckOutcome.dismissed => null,
      UpdateCheckOutcome.notSupported => '目前平台不支援自動更新',
    };
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
