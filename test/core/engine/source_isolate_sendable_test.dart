import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';

// 書源 isolate 沒開（多數測試的情況）時，工作原地執行，但照樣檢查送不送得
// 進書源 isolate：在 App 裡會默默改回主 isolate 的錯誤，在測試裡就要失敗。

Future<int> _sendable(int n) => SourceIsolate.run((_) async => n + 1);

Future<int> _capturesPort(ReceivePort port) =>
    SourceIsolate.run((_) async => port.hashCode);

void main() {
  test('work that only captures data runs in place', () async {
    expect(SourceIsolate.enabled, isFalse);
    expect(await _sendable(1), 2);
  });

  test('work that captures something unsendable fails in tests', () async {
    final port = ReceivePort();
    addTearDown(port.close);

    await expectLater(_capturesPort(port), throwsArgumentError);
  });
}
