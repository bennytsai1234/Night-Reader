import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_settings.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

/// 用 WebDAV 當同步空間（ADR 0039）：填網址、帳號、密碼，連得上才存起來。
class WebDavSettingsPage extends StatefulWidget {
  const WebDavSettingsPage({super.key, this.settings, this.sync});

  final SyncSettings? settings;
  final SyncService? sync;

  @override
  State<WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends State<WebDavSettingsPage> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _user = TextEditingController();
  final TextEditingController _password = TextEditingController();
  late final SyncSettings _settings = widget.settings ?? SyncSettings();
  late final SyncService _sync = widget.sync ?? SyncService.instance;
  bool _connecting = false;
  bool _revealed = false;
  bool _usingWebDav = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSaved());
  }

  Future<void> _loadSaved() async {
    final account = await _settings.webDavAccount();
    final space = await _settings.space();
    if (!mounted) return;
    setState(() {
      if (account != null) {
        _url.text = account.url;
        _user.text = account.user;
        _password.text = account.password;
      }
      _usingWebDav = space == SyncSpace.webdav;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _connect() async {
    final url = _url.text.trim();
    if (url.isEmpty) {
      _say('先填 WebDAV 的網址');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _connecting = true);
    try {
      await _sync.useWebDav((
        url: url,
        user: _user.text.trim(),
        password: _password.text,
      ));
      if (!mounted) return;
      setState(() => _usingWebDav = true);
      final error = _sync.status.value.error;
      _say(error == null ? '已連上，同步好了' : '已連上，但同步失敗：$error');
    } on SyncStoreException catch (error) {
      if (mounted) _say(error.message);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disable() async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '停用同步？',
      message: '這台手機不再和其他手機同步；已經在這台的書、進度、書源與設定都留著。',
      confirmLabel: '停用',
    );
    if (!confirmed || !mounted) return;
    await _sync.disable();
    if (!mounted) return;
    setState(() => _usingWebDav = false);
    _say('已停用同步');
  }

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: 'WebDAV'),
      body: GroupedListView(
        children: [
          GroupedSection(
            footer: '堅果雲要用「第三方應用管理」產生的應用密碼，不是登入密碼。',
            children: [
              GroupedTextFieldRow(
                label: '網址',
                controller: _url,
                hintText: 'https://dav.jianguoyun.com/dav/',
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              GroupedTextFieldRow(
                label: '帳號',
                controller: _user,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              GroupedTextFieldRow(
                label: '密碼',
                controller: _password,
                obscureText: !_revealed,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_connect()),
                suffix: IconButton(
                  tooltip: _revealed ? '隱藏密碼' : '顯示密碼',
                  onPressed: () => setState(() => _revealed = !_revealed),
                  icon: Icon(
                    _revealed
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: chrome.sectionText,
                  ),
                ),
              ),
            ],
          ),
          GroupedSection(
            children: [
              GroupedRow(
                title: _connecting ? '連線中…' : '連線並開始同步',
                accent: true,
                showChevron: false,
                enabled: !_connecting,
                onTap: _connecting ? null : () => unawaited(_connect()),
              ),
              if (_usingWebDav)
                GroupedRow(
                  title: '停用同步',
                  destructive: true,
                  showChevron: false,
                  enabled: !_connecting,
                  onTap: _connecting ? null : () => unawaited(_disable()),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
