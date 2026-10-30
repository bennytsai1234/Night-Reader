import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_volume_keys.dart';

// MainActivity 的攔截狀態只看閱讀器最後送的值；這裡記下送了什麼，
// 並代替原生端送「Activity 重建了」的通知。
void main() {
  const channel = MethodChannel('night_reader/reader_device');
  TestDefaultBinaryMessenger messenger() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final paging = <bool>[];

  setUp(() {
    paging.clear();
    messenger().setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setVolumeKeyPaging') {
        paging.add(call.arguments as bool);
      }
      return null;
    });
  });
  tearDown(() => messenger().setMockMethodCallHandler(channel, null));

  Widget reader({required bool enabled, Key? key}) => MaterialApp(
    home: ReaderV2VolumeKeys(
      key: key,
      enabled: enabled,
      onKey: (_) {},
      child: const SizedBox(),
    ),
  );

  testWidgets('換成一開始不攔的閱讀器時，把上一個的攔截收掉', (tester) async {
    await tester.pumpWidget(reader(enabled: true, key: const ValueKey(1)));
    expect(paging, [true]);

    await tester.pumpWidget(reader(enabled: false, key: const ValueKey(2)));
    expect(paging.last, isFalse, reason: '新的閱讀器接手時不攔，原生端不能還留著攔');

    await tester.pumpWidget(const SizedBox());
    expect(paging.last, isFalse);
  });

  testWidgets('Activity 重建、接上原本的引擎後，閱讀器再說一次要攔', (tester) async {
    await tester.pumpWidget(reader(enabled: true));
    expect(paging, [true]);

    await messenger().handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('volumeKeyReset')),
      (_) {},
    );
    expect(paging, [true, true]);

    await tester.pumpWidget(const SizedBox());
    expect(paging.last, isFalse);
  });
}
