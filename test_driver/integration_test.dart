import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final directory = Platform.environment['NIGHT_READER_SCREENSHOT_DIR'];
      if (directory == null || directory.isEmpty) {
        return false;
      }
      final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
      final file = File('$directory${Platform.pathSeparator}$safeName.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      stdout.writeln(
        'P4V screenshot saved name=$name path=${file.path} bytes=${bytes.length}',
      );
      return true;
    },
    responseDataCallback: (data) async {
      await writeResponseData(
        data,
        testOutputFilename: 'integration_response_data',
      );
    },
    writeResponseOnFailure: true,
  );
}
