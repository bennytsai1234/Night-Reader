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
    // 骨架照一段固定樣子的套件列畫（還不知道有哪些套件），讀到了照真正的
    // 套件先變一次形狀再換場（[GroupedListView.ready]）。
    if (packages == null) {
      return Semantics(
        liveRegion: true,
        label: '正在載入開源許可證',
        child: ExcludeSemantics(
          child: GroupedListView(
            ready: false,
            children: [
              GroupedSection(
                topGap: AppSpacing.md,
                children: [
                  for (final length in _placeholderLengths)
                    GroupedRow(
                      title: 'abcdefghijklmnopqrstuvwxyz'.substring(0, length),
                      onTap: () {},
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (packages.isEmpty) {
      return const AppStateView(
        icon: Icons.description_outlined,
        title: '沒有開源許可證',
      );
    }
    return GroupedListView(
      children: [
        GroupedSection(
          topGap: AppSpacing.md,
          children: [
            for (final MapEntry(key: name, value: entries) in packages.entries)
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

/// 一個套件的授權全文：每份授權一組。段落在背景 isolate 切好（大的授權
/// 上萬字，切段落是逐字掃）。
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
  /// 每份授權的全文，段落之間空一行。null 是還在切。
  List<String>? _texts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final texts = await compute(_licenseTexts, widget.entries);
    if (mounted) setState(() => _texts = texts);
  }

  @override
  Widget build(BuildContext context) {
    final texts = _texts;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassNavHeader(title: widget.package),
      body: texts == null
          // 骨架照一份固定長度的授權畫，切好了照真正的全文變形狀再換場。
          ? Semantics(
              liveRegion: true,
              label: '正在載入授權',
              child: ExcludeSemantics(
                child: GroupedListView(
                  ready: false,
                  children: [
                    _buildLicense(context, _placeholderText, first: true),
                  ],
                ),
              ),
            )
          : GroupedListView(
              children: [
                for (final (index, text) in texts.indexed)
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

  /// 載入中骨架的一份授權：一行標題、幾段長短不一的文字，比一個畫面長。
  static final _placeholderText = [
    'Copyright 2014 The Authors',
    for (final lines in const [3, 5, 2, 6, 4, 3])
      [
        for (var i = 0; i < lines; i++)
          'Permission is hereby granted to use this software in source and binary forms'
              .substring(0, i == lines - 1 ? 38 : 66),
      ].join(' '),
  ].join('\n\n');
}

/// 每份授權切成段落、段落之間空一行。在背景 isolate 跑（[compute]）。
List<String> _licenseTexts(List<LicenseEntry> entries) => [
  for (final entry in entries)
    [for (final paragraph in entry.paragraphs) paragraph.text].join('\n\n'),
];
