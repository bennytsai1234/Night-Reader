import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

/// 會送出什麼：設定頁的說明，與 `PRIVACY.md`、App 的「隱私說明」同一件事
/// （ADR 0053）。
const String aiRepairPrivacyNote =
    '按「AI 修復」時，書源、校驗結果與抓到的網頁會送到這個服務；'
    '登入資料、Cookie 與書源變數不送。';

/// AI 修書源設定（docs/design/screens.md「AI 修書源」）：服務網址、金鑰、
/// 模型，離開頁面就存。
class AiRepairSettingsPage extends StatefulWidget {
  const AiRepairSettingsPage({super.key, this.settings});

  final AiRepairSettings? settings;

  @override
  State<AiRepairSettingsPage> createState() => _AiRepairSettingsPageState();
}

class _AiRepairSettingsPageState extends State<AiRepairSettingsPage> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _key = TextEditingController();
  final TextEditingController _model = TextEditingController();
  late final AiRepairSettings _settings = widget.settings ?? AiRepairSettings();
  bool _loaded = false;
  bool _revealed = false;
  bool _testing = false;

  AiService get _service => (
    baseUrl: _url.text.trim(),
    apiKey: _key.text.trim(),
    model: _model.text.trim(),
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
      _model.text = saved.model;
    } catch (error, stack) {
      AppLog.e('讀 AI 修書源設定失敗', error: error, stackTrace: stack);
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  void dispose() {
    if (_loaded) unawaited(_settings.save(_service));
    _url.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
      await AiChatClient(service).complete([(role: 'user', content: '只回覆 OK')]);
      if (mounted) _say('連得上：${service.model}');
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
      appBar: const GlassNavHeader(title: 'AI 修書源'),
      body: GroupedListView(
        ready: _loaded,
        children: [
          GroupedSection(
            footer: aiRepairPrivacyNote,
            children: [
              GroupedTextFieldRow(
                label: '服務網址',
                controller: _url,
                hintText: 'https://api.openai.com/v1',
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              GroupedTextFieldRow(
                label: '金鑰',
                controller: _key,
                obscureText: !_revealed,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.next,
                suffix: PasswordRevealButton(
                  revealed: _revealed,
                  onPressed: () => setState(() => _revealed = !_revealed),
                ),
              ),
              GroupedTextFieldRow(
                label: '模型',
                controller: _model,
                textInputAction: TextInputAction.done,
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
