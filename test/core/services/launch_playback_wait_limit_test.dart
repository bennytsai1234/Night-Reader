import 'dart:async';

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/system_playback/system_playback.dart';

/// 開媒體工作階段時一直不回應的系統。
class _SilentAudioPlatform extends AudioServicePlatform {
  final _never = Completer<void>();

  @override
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) {}

  @override
  Future<void> configure(ConfigureRequest request) => _never.future;
}

/// 開 App 的底色等系統播放資訊的媒體工作階段（ADR 0018），系統一直不回應時
/// 最多等 [SystemPlayback.launchWait]。另一個檔案：audio_service 一個程序只能
/// 開一次。
void main() {
  testWidgets(
    'launch stops waiting for silent system playback after the limit',
    (tester) async {
      AudioServicePlatform.instance = _SilentAudioPlatform();
      final playback = SystemPlayback();

      var ready = false;
      unawaited(playback.ready().then((_) => ready = true));
      await tester.pump(
        SystemPlayback.launchWait - const Duration(milliseconds: 100),
      );
      expect(ready, isFalse, reason: '上限之前一直等');
      await tester.pump(const Duration(milliseconds: 200));
      expect(ready, isTrue, reason: '超過上限就照常進場');
    },
  );
}
