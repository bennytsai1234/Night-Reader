import 'package:flutter/material.dart';

import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/features/source_manager/source_manager_page.dart';
import 'package:night_reader/features/cache_manager/download_manager_page.dart';
import 'package:night_reader/features/settings/appearance_settings_page.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'package:night_reader/features/settings/reading_stats_page.dart';
import 'tts_settings_page.dart';
import 'backup_settings_page.dart';
import 'package:night_reader/features/about/about_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          _buildProfileCard(context),
          _buildSectionTitle(context, '閱讀'),
          _buildPanel(context, [
            _buildListTile(
              context,
              icon: Icons.timer_outlined,
              title: '閱讀統計',
              summary: '累積閱讀時間',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReadingStatsPage()),
              ),
            ),
            _buildListTile(
              context,
              icon: Icons.tune_outlined,
              title: '閱讀偏好',
              summary: '操作、自動翻頁與內容轉換',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReadingSettingsPage()),
              ),
              isLast: true,
            ),
          ]),
          _buildSectionTitle(context, '書源'),
          _buildPanel(context, [
            _buildListTile(
              context,
              icon: Icons.source_outlined,
              title: '書源管理',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SourceManagerPage()),
              ),
              isLast: true,
            ),
          ]),
          _buildSectionTitle(context, '個人化'),
          _buildPanel(context, [
            _buildListTile(
              context,
              icon: Icons.palette_outlined,
              title: '外觀與主題',
              summary: '介面與閱讀配色',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AppearanceSettingsPage()),
              ),
            ),
            _buildListTile(
              context,
              icon: Icons.volume_up_outlined,
              title: '朗讀與語音',
              summary: '語速、音調與系統語音',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TtsSettingsPage()),
              ),
            ),
            _buildListTile(
              context,
              icon: Icons.backup_outlined,
              title: '備份與還原',
              summary: '本地備份與資料遷移',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BackupSettingsPage()),
              ),
              isLast: true,
            ),
          ]),
          _buildSectionTitle(context, '工具與其他'),
          _buildPanel(context, [
            _buildListTile(
              context,
              icon: Icons.download_for_offline_outlined,
              title: '背景下載佇列',
              summary: '下載任務',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DownloadManagerPage()),
              ),
            ),
            _buildListTile(
              context,
              icon: Icons.info_outline,
              title: '關於夜讀',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPage()),
              ),
              isLast: true,
            ),
          ]),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                '夜讀 · GPL-3.0',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSm.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.7),
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: AppRadius.cardMd,
        boxShadow: theme.cardTheme.shadowColor != null
            ? [
                BoxShadow(
                  color: theme.cardTheme.shadowColor!,
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ]
            : [],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: AppRadius.cardMd,
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.06),
                  spreadRadius: 1,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset('assets/ui/app_icon.webp', fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '夜讀',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamilySerif,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    letterSpacing: 1.6,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '閱讀，從這裡開始',
                  style: AppTextStyles.bodySm.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: AppRadius.pillShape,
            ),
            child: Text(
              '本地',
              style: AppTextStyles.labelXs.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.primary,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
      child: Text(
        title,
        style: AppTextStyles.labelXs.copyWith(
          letterSpacing: 1.8,
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context, List<Widget> children) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: theme.cardTheme.color ?? scheme.surface,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardMd,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildListTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? summary,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                borderRadius: AppRadius.cardSm,
              ),
              child: Icon(icon, color: scheme.primary, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyBase.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  if (summary != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyXs.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
