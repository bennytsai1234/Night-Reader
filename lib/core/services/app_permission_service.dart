import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

enum AppPermissionStatusTone { ok, attention, blocked, neutral }

enum AppPermissionTarget { notification, photos }

enum AppPermissionState {
  denied,
  granted,
  restricted,
  limited,
  permanentlyDenied,
  provisional,
}

abstract interface class AppPermissionGateway {
  Future<AppPermissionState> status(AppPermissionTarget target);

  Future<AppPermissionState> request(AppPermissionTarget target);

  Future<bool> openSystemSettings();
}

typedef AppPermissionPlatformPredicate = bool Function();

class AppPermissionItem {
  const AppPermissionItem({
    required this.title,
    required this.description,
    required this.status,
    required this.tone,
    this.actionLabel,
  });

  final String title;
  final String description;
  final String status;
  final AppPermissionStatusTone tone;
  final String? actionLabel;
}

class AppPermissionSnapshot {
  const AppPermissionSnapshot({required this.items});

  final List<AppPermissionItem> items;
}

class AppPermissionService {
  AppPermissionService({
    AppPermissionGateway? gateway,
    AppPermissionPlatformPredicate? isAndroid,
    AppPermissionPlatformPredicate? isIOS,
  }) : _gateway = gateway ?? const _PermissionHandlerGateway(),
       _isAndroid = isAndroid ?? _isAndroidPlatform,
       _isIOS = isIOS ?? _isIOSPlatform;

  final AppPermissionGateway _gateway;
  final AppPermissionPlatformPredicate _isAndroid;
  final AppPermissionPlatformPredicate _isIOS;

  Future<AppPermissionSnapshot> loadSnapshot() async {
    final items = <AppPermissionItem>[
      await _notificationItem(),
      await _photoLibraryItem(),
      _filePickerItem(),
      _allFilesItem(),
      _backgroundAudioItem(),
    ];
    return AppPermissionSnapshot(items: items);
  }

  Future<bool> requestNotificationForTts() async {
    if (!_isAndroid() && !_isIOS()) return true;
    return _requestIfNeeded(AppPermissionTarget.notification);
  }

  Future<bool> requestPhotoLibraryIfNeeded() async {
    if (!_isIOS()) return true;
    return _requestIfNeeded(AppPermissionTarget.photos);
  }

  Future<bool> openSystemSettings() {
    return _gateway.openSystemSettings();
  }

  Future<AppPermissionItem> _notificationItem() async {
    if (!_isAndroid() && !_isIOS()) {
      return const AppPermissionItem(
        title: '通知',
        description: '此平台不使用行動系統通知權限。',
        status: '不適用',
        tone: AppPermissionStatusTone.neutral,
      );
    }

    final status = await _gateway.status(AppPermissionTarget.notification);
    return AppPermissionItem(
      title: '通知',
      description: 'TTS 朗讀的媒體控制通知會使用此權限；拒絕後仍可朗讀，但通知列控制可能無法顯示。',
      status: _statusLabel(status),
      tone: _statusTone(status),
      actionLabel: _needsSettings(status) ? '開啟系統設定' : '要求權限',
    );
  }

  Future<AppPermissionItem> _photoLibraryItem() async {
    if (!_isIOS()) {
      return const AppPermissionItem(
        title: '相簿',
        description: 'Android 使用系統圖片選取器處理封面更換，不需要夜讀取得整個相簿存取權。',
        status: '不需授權',
        tone: AppPermissionStatusTone.ok,
      );
    }

    final status = await _gateway.status(AppPermissionTarget.photos);
    return AppPermissionItem(
      title: '相簿',
      description: '只在使用者更換書籍封面並選取相簿圖片時使用。',
      status: _statusLabel(status),
      tone: _statusTone(status),
      actionLabel: _needsSettings(status) ? '開啟系統設定' : '要求權限',
    );
  }

  AppPermissionItem _filePickerItem() {
    return const AppPermissionItem(
      title: '檔案選取',
      description: '本地書匯入、備份還原與書源匯入使用系統檔案選擇器，只處理使用者選取的檔案。',
      status: '不需廣域授權',
      tone: AppPermissionStatusTone.ok,
    );
  }

  AppPermissionItem _allFilesItem() {
    return const AppPermissionItem(
      title: '所有檔案存取',
      description: '夜讀不要求 Android 所有檔案存取權，避免取得超出閱讀器必要範圍的儲存權限。',
      status: '未使用',
      tone: AppPermissionStatusTone.ok,
    );
  }

  AppPermissionItem _backgroundAudioItem() {
    if (_isIOS()) {
      return const AppPermissionItem(
        title: '背景音訊',
        description: 'iOS Runner 已啟用 audio background mode，用於 TTS 背景朗讀。',
        status: '已配置',
        tone: AppPermissionStatusTone.ok,
      );
    }
    if (_isAndroid()) {
      return const AppPermissionItem(
        title: '前台媒體服務',
        description:
            'Android 已宣告 foreground media playback service，用於 TTS 媒體控制與背景朗讀。',
        status: '已宣告',
        tone: AppPermissionStatusTone.ok,
      );
    }
    return const AppPermissionItem(
      title: '背景音訊',
      description: '此平台未啟用行動背景音訊權限設計。',
      status: '不適用',
      tone: AppPermissionStatusTone.neutral,
    );
  }

  Future<bool> _requestIfNeeded(AppPermissionTarget target) async {
    final current = await _gateway.status(target);
    if (_isUsable(current)) return true;
    final requested = await _gateway.request(target);
    return _isUsable(requested);
  }

  bool _isUsable(AppPermissionState status) {
    return status == AppPermissionState.granted ||
        status == AppPermissionState.limited ||
        status == AppPermissionState.provisional;
  }

  bool _needsSettings(AppPermissionState status) {
    return status == AppPermissionState.permanentlyDenied ||
        status == AppPermissionState.restricted;
  }

  String _statusLabel(AppPermissionState status) {
    return switch (status) {
      AppPermissionState.granted => '已允許',
      AppPermissionState.limited => '有限存取',
      AppPermissionState.provisional => '暫時允許',
      AppPermissionState.permanentlyDenied => '已永久拒絕',
      AppPermissionState.restricted => '系統限制',
      AppPermissionState.denied => '未允許',
    };
  }

  AppPermissionStatusTone _statusTone(AppPermissionState status) {
    if (_isUsable(status)) return AppPermissionStatusTone.ok;
    if (_needsSettings(status)) return AppPermissionStatusTone.blocked;
    if (status == AppPermissionState.denied) {
      return AppPermissionStatusTone.attention;
    }
    return AppPermissionStatusTone.neutral;
  }
}

bool _isAndroidPlatform() => Platform.isAndroid;

bool _isIOSPlatform() => Platform.isIOS;

class _PermissionHandlerGateway implements AppPermissionGateway {
  const _PermissionHandlerGateway();

  @override
  Future<bool> openSystemSettings() => openAppSettings();

  @override
  Future<AppPermissionState> request(AppPermissionTarget target) async {
    return _toAppState(await _permission(target).request());
  }

  @override
  Future<AppPermissionState> status(AppPermissionTarget target) async {
    return _toAppState(await _permission(target).status);
  }

  Permission _permission(AppPermissionTarget target) {
    return switch (target) {
      AppPermissionTarget.notification => Permission.notification,
      AppPermissionTarget.photos => Permission.photos,
    };
  }

  AppPermissionState _toAppState(PermissionStatus status) {
    return switch (status) {
      PermissionStatus.denied => AppPermissionState.denied,
      PermissionStatus.granted => AppPermissionState.granted,
      PermissionStatus.restricted => AppPermissionState.restricted,
      PermissionStatus.limited => AppPermissionState.limited,
      PermissionStatus.permanentlyDenied =>
        AppPermissionState.permanentlyDenied,
      PermissionStatus.provisional => AppPermissionState.provisional,
    };
  }
}
