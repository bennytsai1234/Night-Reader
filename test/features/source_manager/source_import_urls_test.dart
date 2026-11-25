import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';

import '../../test_helper.dart';

class _UnusedDao extends Fake implements BookSourceDao {}

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

/// 匯入書源檔網址，同 Legado `ImportBookSourceViewModel`：物件裡列著
/// `sourceUrls` 時逐一下載匯入；網址結尾是 `#requestWithoutUA` 的下載時不送
/// 瀏覽器標識。
void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();

  late HttpServer server;
  late String base;
  final userAgents = <String, String?>{};

  String sources(String name) => jsonEncode([
    {'bookSourceName': name, 'bookSourceUrl': 'https://$name.test'},
  ]);

  setUpAll(() async {
    await NetworkService().init(ephemeral: true);
    if (!getIt.isRegistered<NetworkService>()) {
      getIt.registerSingleton<NetworkService>(NetworkService());
    }
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      userAgents[request.uri.path] = request.headers.value('user-agent');
      request.response.headers.contentType = ContentType.json;
      request.response.write(switch (request.uri.path) {
        '/a.json' => sources('a'),
        '/b.json' => sources('b'),
        _ => '[]',
      });
      await request.response.close();
    });
  });

  setUp(userAgents.clear);
  tearDownAll(() => server.close(force: true));

  SourceImportService service() => SourceImportService(dao: _UnusedDao());

  test('an object listing sourceUrls imports every listed file', () async {
    final parsed = await service().parseSourcesDetailedAsync(
      jsonEncode({
        'sourceUrls': ['$base/a.json', '$base/b.json'],
      }),
    );
    expect(parsed.allSources.map((s) => s.bookSourceName), ['a', 'b']);
  });

  test('#requestWithoutUA downloads without a browser identifier', () async {
    final text = await service().fetchImportTextFromUrl(
      '$base/a.json#requestWithoutUA',
    );
    expect(jsonDecode(text), jsonDecode(sources('a')));
    expect(userAgents.keys, ['/a.json']);
    expect(userAgents['/a.json'], isNull);

    await service().fetchImportTextFromUrl('$base/b.json');
    expect(userAgents['/b.json'], isNotNull);
  });

  test('sourceUrls entries honour #requestWithoutUA', () async {
    final parsed = await service().parseSourcesDetailedAsync(
      jsonEncode({
        'sourceUrls': ['$base/a.json#requestWithoutUA'],
      }),
    );
    expect(parsed.allSources.single.bookSourceName, 'a');
    expect(userAgents['/a.json'], isNull);
  });
}
