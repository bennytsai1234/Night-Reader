import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/app_permission_service.dart';

void main() {
  test('loadSnapshot exposes feature-oriented permission rows', () async {
    final snapshot = await AppPermissionService().loadSnapshot();

    expect(snapshot.items.map((item) => item.title), contains('通知'));
    expect(snapshot.items.map((item) => item.title), contains('檔案選取'));
    expect(snapshot.items.map((item) => item.title), contains('所有檔案存取'));
    expect(
      snapshot.items.firstWhere((item) => item.title == '所有檔案存取').status,
      '未使用',
    );
  });
}
