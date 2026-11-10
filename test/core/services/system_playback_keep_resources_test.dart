import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/system_playback/system_playback.dart';
import 'package:xml/xml.dart';

const _tools = 'http://schemas.android.com/tools';

/// `keep.xml` 的 `tools:keep` 留住的資源，例如 `@drawable/audio_service_*`。
List<RegExp> _keptPatterns() {
  final keep = XmlDocument.parse(
    File('android/app/src/main/res/raw/keep.xml').readAsStringSync(),
  ).rootElement.getAttribute('keep', namespaceUri: _tools);
  return [
    for (final entry in (keep ?? '').split(','))
      if (entry.trim().isNotEmpty)
        RegExp(
          '^${RegExp.escape(entry.trim().substring(1)).replaceAll(r'\*', '.*')}\$',
        ),
  ];
}

void main() {
  // 這些圖示只在 Dart 端用名字指定，發布版的資源縮減找不到引用就刪掉。按鈕
  // 圖示不在時，Android 13 以上 audio_service 建「停止」這類按鈕會丟錯，整個
  // 播放狀態送不進系統：通知、鎖定畫面與耳機按鍵都沒有反應。
  test('系統播放資訊用到的圖示，發布版都留著', () {
    final kept = _keptPatterns();
    final icons = [
      SystemPlayback.notificationIcon,
      for (final control in const [
        MediaControl.play,
        MediaControl.pause,
        MediaControl.stop,
        MediaControl.skipToPrevious,
        MediaControl.skipToNext,
        MediaControl.rewind,
        MediaControl.fastForward,
      ])
        control.androidIcon,
    ];

    for (final icon in icons) {
      expect(kept.any((p) => p.hasMatch(icon)), isTrue, reason: icon);
    }
  });
}
