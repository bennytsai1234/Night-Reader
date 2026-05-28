import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/services/source_check_js_worker_probe.dart';

void main() {
  test('JS worker probe completes with a concrete runtime decision', () async {
    final result = await probeSourceCheckJsWorker();

    expect(result.message, isNotEmpty);
    if (result.supported) {
      expect(result.value?.toString(), '2');
    }
  });
}
