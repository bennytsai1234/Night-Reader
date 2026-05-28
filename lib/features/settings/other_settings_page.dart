import 'package:flutter/material.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import 'package:reader/shared/theme/app_text_styles.dart';
import 'package:reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';
import 'package:provider/provider.dart';
import 'data_privacy_settings_page.dart';
import 'settings_provider.dart';

class OtherSettingsPage extends StatefulWidget {
  const OtherSettingsPage({super.key});

  @override
  State<OtherSettingsPage> createState() => _OtherSettingsPageState();
}

class _OtherSettingsPageState extends State<OtherSettingsPage> {
  final ReaderV2PrefsRepository _prefsRepository =
      const ReaderV2PrefsRepository();
  ReaderV2PrefsSnapshot? _readerPrefs;

  @override
  void initState() {
    super.initState();
    _loadReaderPrefs();
  }

  Future<void> _loadReaderPrefs() async {
    final snapshot = await _prefsRepository.load();
    if (!mounted) return;
    setState(() {
      _readerPrefs = snapshot;
    });
  }

  @override
  Widget build(BuildContext context) {
    final readerPrefs = _readerPrefs;
    return Scaffold(
      appBar: AppBar(title: const Text('其他設定')),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return ListView(
            children: [
              _buildSectionTitle('閱讀行為'),
              SwitchListTile(
                title: const Text('預設啟用替換規則'),
                value: settings.replaceEnableDefault,
                onChanged: (v) => settings.setReplaceEnableDefault(v),
              ),
              SwitchListTile(
                title: const Text('顯示加入書架提示'),
                value: readerPrefs?.showAddToShelfAlert ?? true,
                onChanged:
                    readerPrefs == null
                        ? null
                        : (value) {
                          final next = readerPrefs.copyWith(
                            showAddToShelfAlert: value,
                          );
                          setState(() {
                            _readerPrefs = next;
                          });
                          _prefsRepository.saveShowAddToShelfAlert(value);
                        },
              ),
              const Divider(),
              _buildSectionTitle('資料與隱私'),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('資料與隱私'),
                subtitle: const Text('清除 Cookie / WebView 資料、隱私與權限說明'),
                trailing: const Icon(Icons.chevron_right),
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DataPrivacySettingsPage(),
                      ),
                    ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
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
}
