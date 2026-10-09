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

/// 點權限列時要做的事；權限已可用或不適用時沒有動作。
enum AppPermissionAction { request, openSettings }

class AppPermissionItem {
  const AppPermissionItem({
    required this.title,
    required this.status,
    required this.tone,
    this.target,
    this.action,
  });

  final String title;
  final String status;
  final AppPermissionStatusTone tone;
  final AppPermissionTarget? target;
  final AppPermissionAction? action;
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
        status: '不適用',
        tone: AppPermissionStatusTone.neutral,
      );
    }

    final status = await _gateway.status(AppPermissionTarget.notification);
    return AppPermissionItem(
      title: '通知',
      status: _statusLabel(status),
      tone: _statusTone(status),
      target: AppPermissionTarget.notification,
      action: _actionFor(status),
    );
  }

  Future<AppPermissionItem> _photoLibraryItem() async {
    if (!_isIOS()) {
      return const AppPermissionItem(
        title: '相簿',
        status: '不需授權',
        tone: AppPermissionStatusTone.ok,
      );
    }

    final status = await _gateway.status(AppPermissionTarget.photos);
    return AppPermissionItem(
      title: '相簿',
      status: _statusLabel(status),
      tone: _statusTone(status),
      target: AppPermissionTarget.photos,
      action: _actionFor(status),
    );
  }

  AppPermissionItem _filePickerItem() {
    return const AppPermissionItem(
      title: '檔案選取',
      status: '不需廣域授權',
      tone: AppPermissionStatusTone.ok,
    );
  }

  AppPermissionItem _allFilesItem() {
    return const AppPermissionItem(
      title: '所有檔案存取',
      status: '未使用',
      tone: AppPermissionStatusTone.ok,
    );
  }

  AppPermissionItem _backgroundAudioItem() {
    if (_isIOS()) {
      return const AppPermissionItem(
        title: '背景音訊',
        status: '已配置',
        tone: AppPermissionStatusTone.ok,
      );
    }
    if (_isAndroid()) {
      return const AppPermissionItem(
        title: '前台媒體服務',
        status: '已宣告',
        tone: AppPermissionStatusTone.ok,
      );
    }
    return const AppPermissionItem(
      title: '背景音訊',
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

  /// 依目前狀態要求一次權限；已永久拒絕時系統不會再跳對話框，改由
  /// [openSystemSettings] 處理。
  Future<bool> request(AppPermissionTarget target) => _requestIfNeeded(target);

  AppPermissionAction? _actionFor(AppPermissionState status) {
    if (_isUsable(status)) return null;
    return _needsSettings(status)
        ? AppPermissionAction.openSettings
        : AppPermissionAction.request;
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
