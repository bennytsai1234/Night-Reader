import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

/// 開源許可證：App 用到的套件，點了看那個套件的授權全文。從「關於夜讀」
/// 進來。授權來自 [LicenseRegistry]（建置時收集的 NOTICES），讀檔與解壓在
/// 背景 isolate。
class LicensesPage extends StatefulWidget {
  const LicensesPage({super.key, this.licenses});

  /// 測試用；正式頁面讀 [LicenseRegistry.licenses]。
  final Stream<LicenseEntry>? licenses;

  @override
  State<LicensesPage> createState() => _LicensesPageState();
}

class _LicensesPageState extends State<LicensesPage> {
  /// 套件名稱照字母排，各自的授權照收集的順序。null 是還在讀。
  Map<String, List<LicenseEntry>>? _packages;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final packages = <String, List<LicenseEntry>>{};
      await for (final entry in widget.licenses ?? LicenseRegistry.licenses) {
        for (final package in entry.packages) {
          packages.putIfAbsent(package, () => []).add(entry);
        }
      }
      final names = packages.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) return;
      setState(
        () => _packages = {for (final name in names) name: packages[name]!},
      );
    } catch (error, stackTrace) {
      AppLog.e('讀取開源許可證失敗', error: error, stackTrace: stackTrace);
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '開源許可證'),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_failed) {
      return const AppStateView(
        icon: Icons.description_outlined,
        title: '開源許可證載入失敗',
        tone: AppStateTone.error,
      );
    }
    final packages = _packages;
    if (packages != null && packages.isEmpty) {
      return const AppStateView(
        icon: Icons.description_outlined,
        title: '沒有開源許可證',
      );
    }
    // 骨架照一段固定樣子的套件列畫（還不知道有哪些套件），讀到了照真正的
    // 套件先變一次形狀再換場（[GroupedListView.ready]）。
    return GroupedListView(
      ready: packages != null,
      loadingLabel: '正在載入開源許可證',
      children: [
        GroupedSection(
          topGap: AppSpacing.md,
          children: [
            if (packages == null)
              for (final length in _placeholderLengths)
                GroupedRow(
                  title: 'abcdefghijklmnopqrstuvwxyz'.substring(0, length),
                  onTap: () {},
                )
            else
              for (final MapEntry(key: name, value: entries)
                  in packages.entries)
                GroupedRow(
                  title: name,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PackageLicensePage(package: name, entries: entries),
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }

  /// 載入中骨架每一列的字數：長短交錯，像一串套件名稱；比一個畫面高。
  static const _placeholderLengths = [
    9,
    14,
    7,
    18,
    11,
    6,
    16,
    10,
    13,
    8,
    17,
    12,
    9,
    15,
    7,
    11,
  ];
}

/// 一個套件的授權全文：每份授權一組。
///
/// 段落在打開頁面的那一幀就切好（點下去的那一幀可以重，ADR 0036），骨架
/// 直接照真正的全文畫：骨架本來就要把全文排一次才知道形狀，放到背景切也
/// 省不掉主執行緒的排版，還得先畫一份固定樣子的骨架再變形。
class PackageLicensePage extends StatefulWidget {
  const PackageLicensePage({
    super.key,
    required this.package,
    required this.entries,
  });

  final String package;
  final List<LicenseEntry> entries;

  @override
  State<PackageLicensePage> createState() => _PackageLicensePageState();
}

class _PackageLicensePageState extends State<PackageLicensePage> {
  /// 每份授權的全文，段落之間空一行。
  late final List<String> _texts = [
    for (final entry in widget.entries)
      [for (final paragraph in entry.paragraphs) paragraph.text].join('\n\n'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassNavHeader(title: widget.package),
      body: GroupedListView(
        children: [
          for (final (index, text) in _texts.indexed)
            _buildLicense(context, text, first: index == 0),
        ],
      ),
    );
  }

  Widget _buildLicense(
    BuildContext context,
    String text, {
    required bool first,
  }) {
    return GroupedSection(
      topGap: first ? AppSpacing.md : AppGrouped.sectionGap,
      children: [
        GroupedContent(
          padding: const EdgeInsets.symmetric(
            horizontal: AppGrouped.rowPadding,
            vertical: AppSpacing.lg,
          ),
          child: Text(
            text,
            style: AppTextStyles.bodySm.copyWith(
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
