import 'package:flutter/material.dart';

import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/features/source_manager/source_manager_page.dart';
import 'package:night_reader/features/cache_manager/download_manager_page.dart';
import 'package:night_reader/features/settings/appearance_settings_page.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'package:night_reader/features/settings/reading_stats_page.dart';
import 'tts_settings_page.dart';
import 'data_privacy_settings_page.dart';
import 'backup_settings_page.dart';
import 'package:night_reader/features/about/about_page.dart';

/// 「我的」分頁：Telegram 設定頁的結構——置中的 App 頁首，下方為帶上色圖示
/// 的分組清單。
///
/// 圖示顏料依意義固定：硃砂＝閱讀、點金＝紀錄、石青＝網路與書源、
/// 茄紫＝外觀、苔綠＝聲音、茶褐＝資料、墨＝App 資訊。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      // 分頁頁面沒有返回鈕；頁首只提供狀態列下方的漸隱。
      appBar: const GlassNavHeader(automaticallyImplyLeading: false),
      body: GroupedListView(
        children: [
          const _ProfileHeader(),
          GroupedSection(
            header: '閱讀',
            children: [
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.timer_outlined,
                  tint: AppTint.gold,
                ),
                title: '閱讀統計',
                onTap: () => _push(context, const ReadingStatsPage()),
              ),
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.tune_rounded,
                  tint: AppTint.cinnabar,
                ),
                title: '閱讀偏好',
                onTap: () => _push(context, const ReadingSettingsPage()),
              ),
            ],
          ),
          GroupedSection(
            children: [
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.source_outlined,
                  tint: AppTint.azurite,
                ),
                title: '書源管理',
                onTap: () => _push(context, const SourceManagerPage()),
              ),
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.download_rounded,
                  tint: AppTint.azurite,
                ),
                title: '背景下載佇列',
                onTap: () => _push(context, const DownloadManagerPage()),
              ),
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.shield_outlined,
                  tint: AppTint.azurite,
                ),
                title: '資料與隱私',
                onTap: () => _push(context, const DataPrivacySettingsPage()),
              ),
            ],
          ),
          GroupedSection(
            children: [
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.palette_outlined,
                  tint: AppTint.aubergine,
                ),
                title: '外觀與主題',
                onTap: () => _push(context, const AppearanceSettingsPage()),
              ),
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.volume_up_rounded,
                  tint: AppTint.moss,
                ),
                title: '朗讀與語音',
                onTap: () => _push(context, const TtsSettingsPage()),
              ),
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.backup_outlined,
                  tint: AppTint.tea,
                ),
                title: '備份與還原',
                onTap: () => _push(context, const BackupSettingsPage()),
              ),
            ],
          ),
          GroupedSection(
            footer: '夜讀 · GPL-3.0',
            children: [
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.info_outline_rounded,
                  tint: AppTint.ink,
                ),
                title: '關於夜讀',
                onTap: () => _push(context, const AboutPage()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 置中的 App 頁首（Telegram 個人資料頁首的位置）。
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  static const double _iconSize = 88;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppGrouped.margin,
        AppSpacing.md,
        AppGrouped.margin,
        0,
      ),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: AppRadius.cardXl,
              boxShadow: [
                BoxShadow(
                  color: chrome.glassShadow,
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: AppRadius.cardXl,
              child: Image.asset(
                'assets/ui/app_icon.webp',
                width: _iconSize,
                height: _iconSize,
                fit: BoxFit.cover,
                semanticLabel: '夜讀應用程式圖示',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '夜讀',
            style: AppTextStyles.titleXl.copyWith(
              letterSpacing: 1.6,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '本地書庫 · 閱讀，從這裡開始',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm.copyWith(color: chrome.sectionText),
          ),
        ],
      ),
    );
  }
}
