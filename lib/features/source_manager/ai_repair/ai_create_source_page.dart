import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/ai_repair/ai_create_prompt.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/core/background_work/background_work.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/source/source_site.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';
import 'package:night_reader/shared/widgets/glass/glass_menu.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';

import 'ai_repair_page.dart';
import 'ai_repair_settings_page.dart';
import 'repair_runs.dart';

/// 書源管理「加入書源 → 從網站建立（AI）」：有一件正在建立、或建好還沒看過
/// 結果時推回那一頁（ADR 0058），不然推輸入頁（ADR 0082）。
Future<void> openAiCreateSource(
  BuildContext context, {
  RepairRuns? runs,
}) async {
  final repairs = runs ?? RepairRuns.instance;
  final navigator = Navigator.of(context);
  if (repairs.current case final SingleRepairRun current
      when current.creating && !current.isDone) {
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => current.page()),
    );
    return;
  }
  if (!canAiCreateSource()) return;
  await navigator.push(
    MaterialPageRoute<void>(builder: (_) => AiCreateSourcePage(runs: runs)),
  );
}

/// 網址沒寫開頭時補上 https://；不是 http(s) 網站時是 null。
String? aiCreateUrl(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final hasScheme = RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false);
  if (hasScheme.hasMatch(trimmed) &&
      !RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
    return null;
  }
  final url = RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)
      ? trimmed
      : 'https://$trimmed';
  return aiCreateBlankSource(url) == null ? null : url;
}

/// AI 建立書源的輸入頁（docs/design/screens.md「AI 建立書源」）：網址與選填
/// 的樣本書名，按「開始建立」換成建立的頁面（[AiRepairPage]）。
class AiCreateSourcePage extends StatefulWidget {
  const AiCreateSourcePage({super.key, this.settings, this.runs, this.sources});

  final AiRepairSettings? settings;
  final RepairRuns? runs;

  /// 現有的書源；測試換掉它，不讀資料庫。
  final Future<List<BookSource>> Function()? sources;

  @override
  State<AiCreateSourcePage> createState() => _AiCreateSourcePageState();
}

class _AiCreateSourcePageState extends State<AiCreateSourcePage> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _title = TextEditingController();
  AiService? _service;
  bool _starting = false;

  AiRepairSettings get _settings => widget.settings ?? AiRepairSettings();
  RepairRuns get _runs => widget.runs ?? RepairRuns.instance;

  @override
  void initState() {
    super.initState();
    _url.addListener(_redraw);
    BackgroundWork.instance.addListener(_redraw);
    unawaited(_loadService());
  }

  Future<void> _loadService() async {
    final service = await _settings.service();
    if (mounted) setState(() => _service = service);
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    BackgroundWork.instance.removeListener(_redraw);
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: UiText(message)));
  }

  /// 背景工作的位置空著、也沒有還沒看過結果的那一件（ADR 0058）。
  bool get _slotFree => backgroundWorkIdle() && _runs.canStartNew;

  bool get _canStart => !_starting && _url.text.trim().isNotEmpty && _slotFree;

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AiRepairSettingsPage()),
    );
    await _loadService();
  }

  Future<void> _start() async {
    if (!_canStart) return;
    FocusScope.of(context).unfocus();
    final url = aiCreateUrl(_url.text);
    if (url == null) {
      _say('讀不出網址，要是 http 或 https 開頭的網站');
      return;
    }
    setState(() => _starting = true);
    try {
      final service = await _settings.service();
      if (!mounted) return;
      if (service == null) {
        final go = await showAppAlert<bool>(
          context: context,
          title: 'AI 建立書源',
          message: '還沒設定 AI 服務。',
          actions: const [
            AppAlertAction(label: '設定 AI 服務', value: true, isDefault: true),
            AppAlertAction(label: '取消', value: false),
          ],
        );
        if (go == true && mounted) await _openSettings();
        return;
      }
      final blank = aiCreateBlankSource(url)!;
      if (!await _confirmSameSite(blank) || !mounted) return;
      // 讀設定、問使用者的時候別的工作可能開始了。
      if (!_slotFree) return;
      final session = AiRepairSession(
        source: blank,
        service: service,
        create: (url: url, sampleTitle: _title.text.trim()),
      );
      final run = SingleRepairRun(session);
      if (!_runs.adopt(run)) {
        run
          ..disposeWork()
          ..dispose();
        return;
      }
      unawaited(
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute<void>(builder: (_) => run.page())),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// 已經有同一個網站的書源時先問（ADR 0082）：可能是另一類（例如有聲小說
  /// 站），所以可以仍然建立；它帶「異常」時可以改成 AI 修復它。傳回要不要
  /// 接著建立。
  Future<bool> _confirmSameSite(BookSource blank) async {
    final all = await (widget.sources ?? getIt<BookSourceDao>().getAll)();
    final key = siteKey(blank);
    final same = all.where((source) => siteKey(source) == key).firstOrNull;
    if (same == null || !mounted) return true;
    final abnormal = same.hasGroupTag(abnormalSourceGroupTag);
    final choice = await showAppAlert<String>(
      context: context,
      title: 'AI 建立書源',
      message: '已經有同網站的書源「${same.bookSourceName}」。',
      actions: [
        if (abnormal)
          const AppAlertAction(
            label: 'AI 修復它',
            value: 'repair',
            isDefault: true,
          ),
        AppAlertAction(label: '仍然建立', value: 'create', isDefault: !abnormal),
        const AppAlertAction(label: '取消', value: 'cancel'),
      ],
    );
    if (choice == 'repair' && mounted) {
      final navigator = Navigator.of(context);
      navigator.pop();
      unawaited(openAiRepair(navigator.context, same, runs: widget.runs));
    }
    return choice == 'create';
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassNavHeader(
        title: 'AI 建立書源',
        actions: [
          GlassMenuButton<String>(
            entriesBuilder: (_) => const [
              GlassMenuItem(
                value: 'settings',
                icon: Icons.tune_rounded,
                label: 'AI 服務設定',
              ),
            ],
            onSelected: (_) => unawaited(_openSettings()),
          ),
        ],
      ),
      body: GroupedListView(
        children: [
          GroupedSection(
            children: [
              GroupedTextFieldRow(
                controller: _url,
                hintText: '網站網址',
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              GroupedTextFieldRow(
                controller: _title,
                hintText: '站上的一本書名（選填）',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_start()),
              ),
            ],
          ),
          GroupedSection(
            children: [
              if (service != null)
                GroupedRow(
                  title: '送到',
                  value:
                      '${Uri.tryParse(service.baseUrl)?.host ?? service.baseUrl}'
                      ' · ${service.model}',
                  translateValue: false,
                  showChevron: false,
                ),
              GroupedRow(
                title: '開始建立',
                accent: true,
                showChevron: false,
                enabled: _canStart,
                onTap: _canStart ? () => unawaited(_start()) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
