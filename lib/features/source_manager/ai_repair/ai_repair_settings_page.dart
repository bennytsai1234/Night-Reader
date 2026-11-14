import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/ai_repair/ai_connection_check.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

/// 會送出什麼：設定頁的說明，與 `PRIVACY.md`、App 的「隱私說明」同一件事
/// （ADR 0054）。
const String aiRepairPrivacyNote =
    '按「AI 修復」或「修復異常書源」時，書源、校驗結果與抓到的網頁會送到這個服務；'
    '登入資料、Cookie 的值與書源變數不送。';

/// AI 服務設定（docs/design/screens.md「AI 服務」）：常用服務、服務網址、
/// 金鑰、模型（從服務列出的清單選）、思考程度、同時修幾個網站，離開頁面
/// 就存。
class AiRepairSettingsPage extends StatefulWidget {
  const AiRepairSettingsPage({super.key, this.settings, this.listModels});

  final AiRepairSettings? settings;

  /// 向服務要模型清單；沒給時用 [AiChatClient.listModels]（測試換掉它）。
  final Future<List<String>> Function(AiService service)? listModels;

  @override
  State<AiRepairSettingsPage> createState() => _AiRepairSettingsPageState();
}

class _AiRepairSettingsPageState extends State<AiRepairSettingsPage> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _key = TextEditingController();
  late final AiRepairSettings _settings = widget.settings ?? AiRepairSettings();
  bool _loaded = false;
  bool _revealed = false;
  bool _testing = false;
  bool _listing = false;

  /// 服務換了（選了別的常用服務、改了網址或金鑰）就加一：還在等的模型清單
  /// 回來時已經是舊服務的，丟掉（Codex 審查：選了會把舊服務的模型寫進新服務）。
  int _serviceVersion = 0;

  String _model = '';

  /// 思考程度（[aiEfforts] 的值）。
  String _effort = '';

  int _concurrency = aiDefaultConcurrency;

  AiService get _service => (
    baseUrl: _url.text.trim(),
    apiKey: _key.text.trim(),
    model: _model,
    effort: _effort,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final saved = await _settings.read();
      _url.text = saved.baseUrl;
      _key.text = saved.apiKey;
      _model = saved.model;
      _effort = saved.effort;
      _concurrency = await _settings.concurrency();
    } catch (error, stack) {
      AppLog.e('讀 AI 服務設定失敗', error: error, stackTrace: stack);
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  void dispose() {
    if (_loaded) unawaited(_settings.save(_service));
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 思考程度：低的回得快、可能比較常走錯方向；服務預設不送這個參數。
  Future<void> _pickEffort(BuildContext rowContext) async {
    FocusScope.of(context).unfocus();
    final picked = await showGlassMenu<String>(
      context: rowContext,
      anchor: globalRectOf(rowContext),
      entries: [
        for (final MapEntry(key: value, value: label) in aiEfforts.entries)
          GlassMenuItem(value: value, label: label, checked: value == _effort),
      ],
    );
    if (picked != null && mounted) setState(() => _effort = picked);
  }

  Future<void> _pickPreset(BuildContext rowContext) async {
    FocusScope.of(context).unfocus();
    final current = aiServicePresetOf(_url.text);
    final picked = await showGlassMenu<String>(
      context: rowContext,
      anchor: globalRectOf(rowContext),
      entries: [
        for (final preset in aiServicePresets)
          GlassMenuItem(
            value: preset.name,
            label: preset.name,
            subtitle: preset.model == null ? null : '${preset.model}，夜讀實測過',
            checked: identical(preset, current),
          ),
        const GlassMenuDivider(),
        GlassMenuItem(value: '', label: '自己填網址', checked: current == null),
      ],
    );
    if (picked == null || !mounted) return;
    if (picked.isEmpty) {
      setState(() {
        _serviceVersion++;
        _url.clear();
      });
      return;
    }
    final preset = aiServicePresets.firstWhere((p) => p.name == picked);
    if (identical(preset, current)) return;
    // 換了服務，原本的模型多半不在新服務上：有實測過的就填它，沒有的讓
    // 使用者從新服務列出的模型選。
    setState(() {
      _serviceVersion++;
      _url.text = preset.baseUrl;
      _model = preset.model ?? '';
    });
  }

  /// 模型從服務列出的清單選；列不出來（網址錯、服務不給清單）或清單裡沒有
  /// 時，自己輸入。
  Future<void> _pickModel(BuildContext rowContext) async {
    FocusScope.of(context).unfocus();
    final service = _service;
    if (service.baseUrl.isEmpty) {
      _say('先選服務或填服務網址');
      return;
    }
    setState(() => _listing = true);
    final version = _serviceVersion;
    List<String> models = const [];
    try {
      models = await (widget.listModels ?? _listModels)(service);
    } on AiServiceException catch (error) {
      if (mounted) _say('列不出模型：${error.message}');
    } catch (error) {
      if (mounted) _say('列不出模型：$error');
    } finally {
      if (mounted) setState(() => _listing = false);
    }
    if (!mounted || !rowContext.mounted || version != _serviceVersion) return;
    final picked = models.isEmpty
        ? ''
        : await showGlassMenu<String>(
            context: rowContext,
            anchor: globalRectOf(rowContext),
            entries: [
              for (final model in models)
                GlassMenuItem(
                  value: model,
                  label: model,
                  subtitle: aiModelTested(service.baseUrl, model)
                      ? '夜讀實測過'
                      : null,
                  checked: model == _model,
                ),
              const GlassMenuDivider(),
              const GlassMenuItem(value: '', label: '自己輸入模型名稱'),
            ],
          );
    if (picked == null || !mounted || version != _serviceVersion) return;
    if (picked.isNotEmpty) {
      setState(() => _model = picked);
      return;
    }
    final typed = await showStatefulAppAlert<String>(
      context: context,
      fieldTexts: [_model],
      builder: (dialogContext, _, fields) {
        void submit() => Navigator.of(dialogContext).pop(fields.single.text);
        return AppAlert<bool>(
          title: '模型名稱',
          content: AlertTextField(controller: fields.single, autofocus: true),
          actions: const [
            AppAlertAction(label: '取消', value: false),
            AppAlertAction(label: '確定', value: true, isDefault: true),
          ],
          onAction: (confirmed) =>
              confirmed ? submit() : Navigator.of(dialogContext).pop(),
        );
      },
    );
    if (typed != null && mounted && version == _serviceVersion) {
      setState(() => _model = typed.trim());
    }
  }

  static Future<List<String>> _listModels(AiService service) =>
      AiChatClient(service).listModels();

  Future<void> _pickConcurrency(BuildContext rowContext) async {
    FocusScope.of(context).unfocus();
    final picked = await showGlassMenu<int>(
      context: rowContext,
      anchor: globalRectOf(rowContext),
      entries: [
        for (final value in aiConcurrencyChoices)
          GlassMenuItem(
            value: value,
            label: '$value 個',
            subtitle: value == aiDefaultConcurrency ? '預設' : null,
            checked: value == _concurrency,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _concurrency = picked);
    unawaited(_settings.saveConcurrency(picked));
  }

  Future<void> _test() async {
    final service = _service;
    if (service.baseUrl.isEmpty || service.model.isEmpty) {
      _say('先填服務網址與模型');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _testing = true);
    try {
      await _settings.save(service);
      await verifyAiToolConnection(AiChatClient(service));
      if (mounted) _say('連線與工具呼叫正常：${service.model}');
    } on AiServiceException catch (error) {
      if (mounted) _say(error.message);
    } catch (error) {
      if (mounted) _say('連不上：$error');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: 'AI 服務'),
      body: GroupedListView(
        ready: _loaded,
        children: [
          GroupedSection(
            footer: aiRepairPrivacyNote,
            children: [
              Builder(
                builder: (rowContext) => GroupedRow(
                  title: '常用服務',
                  value: aiServicePresetOf(_url.text)?.name ?? '自己填網址',
                  showChevron: false,
                  onTap: () => unawaited(_pickPreset(rowContext)),
                ),
              ),
              GroupedTextFieldRow(
                label: '服務網址',
                onChanged: (_) => setState(() => _serviceVersion++),
                controller: _url,
                hintText: 'https://api.openai.com/v1',
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              GroupedTextFieldRow(
                label: '金鑰',
                controller: _key,
                onChanged: (_) => _serviceVersion++,
                obscureText: !_revealed,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                suffix: PasswordRevealButton(
                  revealed: _revealed,
                  onPressed: () => setState(() => _revealed = !_revealed),
                ),
              ),
              Builder(
                builder: (rowContext) => GroupedRow(
                  title: '模型',
                  value: _listing
                      ? '讀取中…'
                      : _model.isEmpty
                      ? '選擇'
                      : _model,
                  showChevron: false,
                  enabled: !_listing,
                  onTap: () => unawaited(_pickModel(rowContext)),
                ),
              ),
              Builder(
                builder: (rowContext) => GroupedRow(
                  title: '思考程度',
                  value: aiEfforts[_effort],
                  showChevron: false,
                  onTap: () => unawaited(_pickEffort(rowContext)),
                ),
              ),
              Builder(
                builder: (rowContext) => GroupedRow(
                  title: '同時修幾個網站',
                  value: '$_concurrency',
                  showChevron: false,
                  onTap: () => unawaited(_pickConcurrency(rowContext)),
                ),
              ),
            ],
          ),
          GroupedSection(
            children: [
              GroupedRow(
                title: _testing ? '連線中…' : '測試連線',
                accent: true,
                showChevron: false,
                enabled: !_testing,
                onTap: _testing ? null : () => unawaited(_test()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
