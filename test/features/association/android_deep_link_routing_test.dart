import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _android = 'http://schemas.android.com/apk/res/android';

String? _attr(XmlElement element, String name) =>
    element.getAttribute(name, namespaceUri: _android);

/// 會收到帶網址 intent（VIEW 加上 scheme）的 activity。
bool _opensLinks(XmlElement activity) => activity
    .findElements('intent-filter')
    .any(
      (filter) =>
          filter
              .findElements('action')
              .any((a) => _attr(a, 'name') == 'android.intent.action.VIEW') &&
          filter.findElements('data').any((d) => _attr(d, 'scheme') != null),
    );

void main() {
  // 外部連結（legado://、yuedu://）由 app_links 接手。Flutter 預設也會把同一個
  // 網址當成路由 pushNamed，App 沒有這條路由也沒有 onUnknownRoute，App 開著時
  // 收到連結就丟出 Null check 錯誤。
  test('收外部連結的 activity 關掉 Flutter 的深層連結路由', () {
    final manifest = XmlDocument.parse(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
    );
    final activities = manifest
        .findAllElements('activity')
        .where(_opensLinks)
        .toList();
    expect(activities, isNotEmpty);

    for (final activity in activities) {
      final flag = activity
          .findElements('meta-data')
          .where((m) => _attr(m, 'name') == 'flutter_deeplinking_enabled')
          .map((m) => _attr(m, 'value'))
          .toList();
      expect(flag, ['false'], reason: _attr(activity, 'name'));
    }
  });
}
