import 'package:flutter/material.dart';

import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/features/source_manager/source_manager_page.dart';
import 'package:night_reader/features/cache_manager/download_manager_page.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'tts_settings_page.dart';
import 'backup_settings_page.dart';
import 'package:night_reader/features/about/about_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '我的',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamilySerif,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _buildProfileCard(context),

          _buildSectionTitle(context, '主題與外觀'),
          _buildPanel(context, [
            _buildListTile(
              context,
              icon: Icons.palette_outlined,
              title: '閱讀排版與主題',
              summary: '切換閱讀背景、字體、字號',
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ReadingSettingsPage(),
                    ),
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
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SourceManagerPage(),
                    ),
                  ),
              isLast: true,
            ),
          ]),

          _buildSectionTitle(context, '個人化'),
          _buildPanel(context, [
            _buildListTile(
              context,
              icon: Icons.volume_up_outlined,
              title: '朗讀與語音',
              summary: '語速、音調、系統語音',
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TtsSettingsPage()),
                  ),
            ),
            _buildListTile(
              context,
              icon: Icons.backup_outlined,
              title: '備份與還原',
              summary: '本地備份、數據遷移',
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BackupSettingsPage(),
                    ),
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
              summary: '查看、暫停、重試與刪除下載任務',
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DownloadManagerPage(),
                    ),
                  ),
            ),
            _buildListTile(
              context,
              icon: Icons.info_outline,
              title: '關於夜讀',
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AboutPage()),
                  ),
              isLast: true,
            ),
          ]),

          const SizedBox(height: 24),
          Center(
            child: Text(
              '夜讀 · GPL-3.0',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                letterSpacing: 2.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? AppPalette.cinnabarDark : AppPalette.cinnabar;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: Border.all(
          color: isDark ? const Color(0x1EF4EDD7) : const Color(0x16241C10),
        ),
        borderRadius: AppRadius.cardLg,
        boxShadow:
            theme.cardTheme.shadowColor != null
                ? [
                  BoxShadow(
                    color: theme.cardTheme.shadowColor!,
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
                : [],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F14110D),
                  blurRadius: 0,
                  spreadRadius: 1,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset('assets/app-icon.png', fit: BoxFit.cover),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '夜讀',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamilySerif,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    letterSpacing: 2.0,
                    color: isDark ? AppPalette.ink50 : AppPalette.ink700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '閱讀，從這裡開始',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppPalette.ink200 : AppPalette.ink300,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '本地',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: accent,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? AppPalette.cinnabarDark : AppPalette.cinnabar;

    return Padding(
      padding: const EdgeInsets.only(left: 22, right: 22, top: 20, bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 2.4,
          color: accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context, List<Widget> children) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: Border.all(
          color: isDark ? const Color(0x1EF4EDD7) : const Color(0x16241C10),
        ),
        borderRadius: AppRadius.cardLg,
        boxShadow:
            theme.cardTheme.shadowColor != null
                ? [
                  BoxShadow(
                    color: theme.cardTheme.shadowColor!,
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
                : [],
      ),
      child: Column(children: children),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? AppPalette.cinnabarDark : AppPalette.cinnabar;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border:
              isLast
                  ? null
                  : Border(
                    bottom: BorderSide(
                      color:
                          isDark
                              ? const Color(0x1EF4EDD7)
                              : const Color(0x16241C10),
                    ),
                  ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: AppRadius.cardSm,
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? AppPalette.ink50 : AppPalette.ink700,
                    ),
                  ),
                  if (summary != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppPalette.ink200 : AppPalette.ink300,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isDark ? AppPalette.ink200 : AppPalette.ink300,
            ),
          ],
        ),
      ),
    );
  }
}
