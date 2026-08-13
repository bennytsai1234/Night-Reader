import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/app_permission_service.dart';

void main() {
  test('loadSnapshot exposes feature-oriented permission rows', () async {
    final service = AppPermissionService();
    final snapshot = await service.loadSnapshot();

    expect(snapshot.items.map((item) => item.title), contains('通知'));
    expect(snapshot.items.map((item) => item.title), contains('檔案選取'));
    expect(snapshot.items.map((item) => item.title), contains('所有檔案存取'));
    expect(
      snapshot.items.firstWhere((item) => item.title == '通知').status,
      '不適用',
    );
    expect(
      snapshot.items.firstWhere((item) => item.title == '所有檔案存取').status,
      '未使用',
    );
    expect(await service.requestNotificationForTts(), isTrue);
    expect(await service.requestPhotoLibraryIfNeeded(), isTrue);
  });

  test('Android permanently denied notification is blocked', () async {
    final gateway = _FakePermissionGateway(
      statuses: const {
        AppPermissionTarget.notification: AppPermissionState.permanentlyDenied,
      },
    );
    final service = AppPermissionService(
      gateway: gateway,
      isAndroid: () => true,
      isIOS: () => false,
    );

    final snapshot = await service.loadSnapshot();
    final notification = snapshot.items.firstWhere(
      (item) => item.title == '通知',
    );

    expect(notification.status, '已永久拒絕');
    expect(notification.tone, AppPermissionStatusTone.blocked);
    expect(notification.actionLabel, '開啟系統設定');
    expect(
      snapshot.items.firstWhere((item) => item.title == '相簿').status,
      '不需授權',
    );
    expect(gateway.statusCalls[AppPermissionTarget.notification], 1);
    expect(gateway.statusCalls[AppPermissionTarget.photos], isNull);
  });

  test('denied notification requests once and returns granted', () async {
    final gateway = _FakePermissionGateway(
      statuses: const {
        AppPermissionTarget.notification: AppPermissionState.denied,
      },
      requestResults: const {
        AppPermissionTarget.notification: AppPermissionState.granted,
      },
    );
    final service = AppPermissionService(
      gateway: gateway,
      isAndroid: () => true,
      isIOS: () => false,
    );

    expect(await service.requestNotificationForTts(), isTrue);
    expect(gateway.statusCalls[AppPermissionTarget.notification], 1);
    expect(gateway.requestCalls[AppPermissionTarget.notification], 1);
  });

  test('already granted notification does not request again', () async {
    final gateway = _FakePermissionGateway(
      statuses: const {
        AppPermissionTarget.notification: AppPermissionState.granted,
      },
    );
    final service = AppPermissionService(
      gateway: gateway,
      isAndroid: () => true,
      isIOS: () => false,
    );

    expect(await service.requestNotificationForTts(), isTrue);
    expect(gateway.statusCalls[AppPermissionTarget.notification], 1);
    expect(gateway.requestCalls[AppPermissionTarget.notification], isNull);
  });

  test('iOS limited photos and provisional notifications are usable', () async {
    final gateway = _FakePermissionGateway(
      statuses: const {
        AppPermissionTarget.notification: AppPermissionState.provisional,
        AppPermissionTarget.photos: AppPermissionState.limited,
      },
    );
    final service = AppPermissionService(
      gateway: gateway,
      isAndroid: () => false,
      isIOS: () => true,
    );

    final snapshot = await service.loadSnapshot();
    final notification = snapshot.items.firstWhere(
      (item) => item.title == '通知',
    );
    final photos = snapshot.items.firstWhere((item) => item.title == '相簿');

    expect(notification.status, '暫時允許');
    expect(notification.tone, AppPermissionStatusTone.ok);
    expect(notification.actionLabel, '要求權限');
    expect(photos.status, '有限存取');
    expect(photos.tone, AppPermissionStatusTone.ok);
    expect(photos.actionLabel, '要求權限');
    expect(await service.requestNotificationForTts(), isTrue);
    expect(await service.requestPhotoLibraryIfNeeded(), isTrue);
    expect(gateway.requestCalls, isEmpty);
    expect(gateway.statusCalls[AppPermissionTarget.notification], 2);
    expect(gateway.statusCalls[AppPermissionTarget.photos], 2);
  });

  test('openSystemSettings delegates to the gateway', () async {
    final gateway = _FakePermissionGateway(openSettingsResult: false);
    final service = AppPermissionService(
      gateway: gateway,
      isAndroid: () => false,
      isIOS: () => false,
    );

    expect(await service.openSystemSettings(), isFalse);
    expect(gateway.openSettingsCalls, 1);
  });
}

class _FakePermissionGateway implements AppPermissionGateway {
  _FakePermissionGateway({
    this.statuses = const {},
    this.requestResults = const {},
    this.openSettingsResult = true,
  });

  final Map<AppPermissionTarget, AppPermissionState> statuses;
  final Map<AppPermissionTarget, AppPermissionState> requestResults;
  final bool openSettingsResult;
  final Map<AppPermissionTarget, int> statusCalls = {};
  final Map<AppPermissionTarget, int> requestCalls = {};
  int openSettingsCalls = 0;

  @override
  Future<bool> openSystemSettings() async {
    openSettingsCalls += 1;
    return openSettingsResult;
  }

  @override
  Future<AppPermissionState> request(AppPermissionTarget target) async {
    requestCalls.update(target, (count) => count + 1, ifAbsent: () => 1);
    return requestResults[target] ?? AppPermissionState.denied;
  }

  @override
  Future<AppPermissionState> status(AppPermissionTarget target) async {
    statusCalls.update(target, (count) => count + 1, ifAbsent: () => 1);
    return statuses[target] ?? AppPermissionState.denied;
  }
}
