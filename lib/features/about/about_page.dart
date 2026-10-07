import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'crash_log_page.dart';
import 'external_url_launcher.dart';
import 'update_check_runner.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '0.1.0';
  String _buildNumber = '1';
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '關於'),
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
                subtitle: 'github.com/bennytsai1234/Night-Reader',
                onTap:
                    () => launchExternalUrlWithFeedback(
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
                onTap:
                    () => showLicensePage(
                      context: context,
                      applicationName: '夜讀',
                      applicationVersion: '$_version ($_buildNumber)',
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
            ],
          ),
          GroupedSection(
            header: '系統工具',
            footer: '本專案為開源學習作品，不提供任何內容服務。所有數據由使用者自行導入。',
            children: [
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.system_update_alt_rounded,
                  tint: AppTint.moss,
                ),
                title: '檢查更新',
                value: _checkingUpdate ? '檢查中…' : 'v$_version',
                trailing:
                    _checkingUpdate
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
                  Icons.report_problem_outlined,
                  tint: AppTint.rust,
                ),
                title: '崩潰日誌',
                onTap:
                    () => Navigator.push(
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
            'v$_version',
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
