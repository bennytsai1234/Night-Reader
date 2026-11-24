import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/platform/app_permission_service.dart';

class _FakeGateway implements AppPermissionGateway {
  _FakeGateway(this.state);

  AppPermissionState state;

  @override
  Future<AppPermissionState> status(AppPermissionTarget target) async => state;

  @override
  Future<AppPermissionState> request(AppPermissionTarget target) async => state;

  @override
  Future<bool> openSystemSettings() async => true;
}

void main() {
  Future<AppPermissionItem> notificationRow(AppPermissionState state) async {
    final service = AppPermissionService(
      gateway: _FakeGateway(state),
      isAndroid: () => true,
      isIOS: () => false,
    );
    final snapshot = await service.loadSnapshot();
    return snapshot.items.firstWhere((item) => item.title == '通知');
  }

  test('the notification row acts according to its state', () async {
    expect((await notificationRow(AppPermissionState.granted)).action, isNull);
    expect(
      (await notificationRow(AppPermissionState.denied)).action,
      AppPermissionAction.request,
    );
    expect(
      (await notificationRow(AppPermissionState.permanentlyDenied)).action,
      AppPermissionAction.openSettings,
    );
    expect(
      (await notificationRow(AppPermissionState.denied)).target,
      AppPermissionTarget.notification,
    );
  });

  test(
    'only iPhone lists Face ID, and a refusal points to the settings',
    () async {
      Future<List<AppPermissionItem>> rows({
        required bool iOS,
        String? faceId,
      }) async {
        final service = AppPermissionService(
          gateway: _FakeGateway(AppPermissionState.granted),
          isAndroid: () => !iOS,
          isIOS: () => iOS,
          faceIdStatus: () async => faceId,
        );
        final loading = service.loadingSnapshot().items;
        final loaded = (await service.loadSnapshot()).items;
        expect(
          loaded.map((item) => item.title),
          loading.map((item) => item.title),
          reason: 'the skeleton has the same rows',
        );
        return loaded;
      }

      expect(
        (await rows(iOS: false)).map((item) => item.title),
        isNot(contains('Face ID')),
      );
      AppPermissionItem faceIdRow(List<AppPermissionItem> items) =>
          items.firstWhere((item) => item.title == 'Face ID');
      expect(
        faceIdRow(await rows(iOS: true, faceId: 'available')).status,
        '可用',
      );
      final denied = faceIdRow(await rows(iOS: true, faceId: 'denied'));
      expect(denied.status, '未允許');
      expect(denied.action, AppPermissionAction.openSettings);
      expect(faceIdRow(await rows(iOS: true, faceId: 'none')).status, '不適用');
    },
  );
}
