import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/app_permission_service.dart';

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
}
