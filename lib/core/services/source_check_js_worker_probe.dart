import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';

class SourceCheckJsWorkerProbeResult {
  final bool supported;
  final String message;
  final Object? value;

  const SourceCheckJsWorkerProbeResult({
    required this.supported,
    required this.message,
    this.value,
  });
}

Future<SourceCheckJsWorkerProbeResult> probeSourceCheckJsWorker() async {
  try {
    final payload = await compute(_probeJsRuntimeInWorker, '1 + 1');
    return SourceCheckJsWorkerProbeResult(
      supported: payload['supported'] == true,
      message: payload['message']?.toString() ?? '',
      value: payload['value'],
    );
  } catch (error) {
    return SourceCheckJsWorkerProbeResult(
      supported: false,
      message: 'JS worker isolate probe failed: $error',
    );
  }
}

Map<String, Object?> _probeJsRuntimeInWorker(String script) {
  JavascriptRuntime? runtime;
  try {
    runtime = getJavascriptRuntime();
    final result = runtime.evaluate(script);
    if (result.isError) {
      return <String, Object?>{
        'supported': false,
        'message': result.stringResult,
      };
    }
    return <String, Object?>{
      'supported': true,
      'message': 'JS runtime initialized in worker isolate',
      'value': result.rawResult,
    };
  } catch (error) {
    return <String, Object?>{'supported': false, 'message': error.toString()};
  } finally {
    runtime?.dispose();
  }
}
