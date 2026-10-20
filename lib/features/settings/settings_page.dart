import 'package:flutter/material.dart';

import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
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

/// 「我的」分頁：頁首置中標題「我的」（同書架、發現），下方為帶上色圖示的
/// 分組清單。每一列都是進入下一頁的入口，不放開關（ADR 0015）。
///
/// 依用途分兩組：閱讀（偏好、外觀、朗讀、統計），書與資料（書源、下載、
/// 備份、隱私與關於）；組數少，組間的空帶只有一條。
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
      // 從閱讀器推入時才有返回鈕。
      appBar: GlassNavHeader(
        title: '我的',
        automaticallyImplyLeading:
            ModalRoute.of(context)?.impliesAppBarDismissal ?? false,
      ),
      body: GroupedListView(
        children: [
          GroupedSection(
            topGap: AppSpacing.lg,
            children: [
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.tune_rounded,
                  tint: AppTint.cinnabar,
                ),
                title: '閱讀偏好',
                onTap: () => _push(context, const ReadingSettingsPage()),
              ),
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
                  Icons.timer_outlined,
                  tint: AppTint.gold,
                ),
                title: '閱讀統計',
                onTap: () => _push(context, const ReadingStatsPage()),
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
                  Icons.backup_outlined,
                  tint: AppTint.tea,
                ),
                title: '備份與還原',
                onTap: () => _push(context, const BackupSettingsPage()),
              ),
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.shield_outlined,
                  tint: AppTint.azurite,
                ),
                title: '資料與隱私',
                onTap: () => _push(context, const DataPrivacySettingsPage()),
              ),
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
