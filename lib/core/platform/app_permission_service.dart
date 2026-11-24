import 'dart:io';

import 'package:flutter/services.dart';
import 'package:night_reader/core/app_lock/app_lock.dart';
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

/// iPhone 的 Face ID 能不能給夜讀用：`none`（這台不是 Face ID）、
/// `available`、`denied`（使用者不讓夜讀用）、`notEnrolled`（還沒設定）。
typedef FaceIdStatusReader = Future<String?> Function();

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
    FaceIdStatusReader? faceIdStatus,
  }) : _gateway = gateway ?? const _PermissionHandlerGateway(),
       _isAndroid = isAndroid ?? _isAndroidPlatform,
       _isIOS = isIOS ?? _isIOSPlatform,
       _faceIdStatus = faceIdStatus ?? _readFaceIdStatus;

  final AppPermissionGateway _gateway;
  final AppPermissionPlatformPredicate _isAndroid;
  final AppPermissionPlatformPredicate _isIOS;
  final FaceIdStatusReader _faceIdStatus;

  /// 權限尚未查完時仍能知道固定的列結構；狀態文字拿到後才換成真值。
  /// 與 [loadSnapshot] 使用相同的列順序和平台分支。
  AppPermissionSnapshot loadingSnapshot() => _snapshot(
    AppPermissionItem(
      title: '通知',
      status: _isAndroid() || _isIOS() ? '讀取中…' : '不適用',
      tone: AppPermissionStatusTone.neutral,
    ),
    AppPermissionItem(
      title: '相簿',
      status: _isIOS() ? '讀取中…' : '不需授權',
      tone: AppPermissionStatusTone.neutral,
    ),
    _isIOS()
        ? const AppPermissionItem(
            title: 'Face ID',
            status: '讀取中…',
            tone: AppPermissionStatusTone.neutral,
          )
        : null,
  );

  Future<AppPermissionSnapshot> loadSnapshot() async => _snapshot(
    await _notificationItem(),
    await _photoLibraryItem(),
    _isIOS() ? await _faceIdItem() : null,
  );

  /// 等待中與完成後的列由同一處組裝，不會因新增權限讓兩邊列數分岔。Face ID
  /// 只有 iPhone 有（「解鎖才能打開」，ADR 0083；Android 的辨識不用詢問）。
  AppPermissionSnapshot _snapshot(
    AppPermissionItem notification,
    AppPermissionItem photos,
    AppPermissionItem? faceId,
  ) => AppPermissionSnapshot(
    items: [
      notification,
      photos,
      ?faceId,
      _filePickerItem(),
      _allFilesItem(),
      _backgroundAudioItem(),
    ],
  );

  /// 通知權限：朗讀的播放控制與背景工作的進度（ADR 0058）都要；第一次用到時才問。
  Future<bool> requestNotification() async {
    if (!_isAndroid() && !_isIOS()) return true;
    return _requestIfNeeded(AppPermissionTarget.notification);
  }

  Future<bool> requestPhotoLibraryIfNeeded() async {
    if (!_isIOS()) return true;
    return _requestIfNeeded(AppPermissionTarget.photos);
  }

  /// 系統設定是夜讀自己打開的，回來不算離開（ADR 0083）；Android 的
  /// permission_handler 不經過夜讀的視窗打開，這裡自己記。
  Future<bool> openSystemSettings() async {
    await AppLock.instance.markOwnExcursion();
    final opened = await _gateway.openSystemSettings();
    if (!opened) await AppLock.instance.clearOwnExcursion();
    return opened;
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

  Future<AppPermissionItem> _faceIdItem() async {
    String? status;
    try {
      status = await _faceIdStatus();
    } catch (_) {
      status = null;
    }
    return switch (status) {
      'available' => const AppPermissionItem(
        title: 'Face ID',
        status: '可用',
        tone: AppPermissionStatusTone.ok,
      ),
      'denied' => const AppPermissionItem(
        title: 'Face ID',
        status: '未允許',
        tone: AppPermissionStatusTone.blocked,
        action: AppPermissionAction.openSettings,
      ),
      'notEnrolled' => const AppPermissionItem(
        title: 'Face ID',
        status: '未設定',
        tone: AppPermissionStatusTone.neutral,
      ),
      _ => const AppPermissionItem(
        title: 'Face ID',
        status: '不適用',
        tone: AppPermissionStatusTone.neutral,
      ),
    };
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

Future<String?> _readFaceIdStatus() =>
    const MethodChannel('night_reader/app_lock')
        .invokeMethod<String>('faceIdStatus');

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
