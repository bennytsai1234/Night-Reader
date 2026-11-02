import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_settings.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:night_reader/features/settings/webdav_settings_page.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

/// 選這台手機的同步空間（ADR 0039）：Google 雲端硬碟或 WebDAV，每台自己選。
/// Google 雲端硬碟只在 Android：iOS 版是使用者自己重新簽章安裝的，Google
/// 登入認不得改過的套件名。
class SyncSpacePage extends StatefulWidget {
  const SyncSpacePage({super.key, this.settings, this.sync});

  final SyncSettings? settings;
  final SyncService? sync;

  @override
  State<SyncSpacePage> createState() => _SyncSpacePageState();
}

class _SyncSpacePageState extends State<SyncSpacePage> {
  late final SyncSettings _settings = widget.settings ?? SyncSettings();
  late final SyncService _sync = widget.sync ?? SyncService.instance;
  SyncSpace _space = SyncSpace.none;
  String? _googleAccount;
  String? _webDavUrl;
  bool _connecting = false;

  static bool get _googleAvailable =>
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final space = await _settings.space();
    final google = await _settings.googleAccount();
    final webDav = await _settings.webDavAccount();
    if (!mounted) return;
    setState(() {
      _space = space;
      _googleAccount = google;
      _webDavUrl = webDav?.url;
    });
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _useGoogleDrive() async {
    setState(() => _connecting = true);
    try {
      await _sync.useGoogleDrive();
      await _load();
      if (!mounted) return;
      final error = _sync.status.value.error;
      _say(error == null ? '已連上 Google 雲端硬碟，同步好了' : '已連上，但同步失敗：$error');
    } on SyncStoreException catch (error) {
      if (mounted) _say(error.message);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _openWebDav() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => WebDavSettingsPage(settings: _settings, sync: _sync),
      ),
    );
    await _load();
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
    await _load();
    if (mounted) _say('已停用同步');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '同步空間'),
      body: GroupedListView(
        children: [
          GroupedSection(
            footer: _googleAvailable
                ? 'Google 雲端硬碟用 App 專屬的隱藏資料夾，看不到也碰不到你其他的檔案。每台手機選同一個空間（同一個 Google 帳號，或同一個 WebDAV）才會同步。'
                : '每台手機選同一個 WebDAV 才會同步。',
            children: [
              if (_googleAvailable)
                GroupedCheckRow(
                  title: _connecting ? '登入中…' : 'Google 雲端硬碟',
                  subtitle: _space == SyncSpace.googleDrive
                      ? _googleAccount
                      : null,
                  selected: _space == SyncSpace.googleDrive,
                  enabled: !_connecting,
                  onTap: _connecting || _space == SyncSpace.googleDrive
                      ? null
                      : () => unawaited(_useGoogleDrive()),
                ),
              GroupedCheckRow(
                title: 'WebDAV',
                subtitle: _space == SyncSpace.webdav ? _webDavUrl : null,
                selected: _space == SyncSpace.webdav,
                enabled: !_connecting,
                onTap: _connecting ? null : () => unawaited(_openWebDav()),
              ),
            ],
          ),
          if (_space != SyncSpace.none)
            GroupedSection(
              children: [
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
