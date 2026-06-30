import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_runtime.dart';

import 'scroll_reader_v2_viewport.dart';

class EngineReaderV2Screen extends StatefulWidget {
  const EngineReaderV2Screen({
    super.key,
    required this.runtime,
    required this.backgroundColor,
    required this.textColor,
    required this.style,
    this.onContentTapUp,
    this.viewportController,
    this.ttsHighlight,
  });

  final ReaderV2Runtime runtime;
  final Color backgroundColor;
  final Color textColor;
  final ReaderV2Style style;
  final GestureTapUpCallback? onContentTapUp;
  final ReaderV2ViewportController? viewportController;
  final ReaderV2TtsHighlight? ttsHighlight;

  @override
  State<EngineReaderV2Screen> createState() => _EngineReaderV2ScreenState();
}

class _EngineReaderV2ScreenState extends State<EngineReaderV2Screen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addTimingsCallback(_handleFrameTimings);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(_handleFrameTimings);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      unawaited(widget.runtime.flushProgress());
    }
  }

  void _handleFrameTimings(List<FrameTiming> timings) {
    if (!mounted || timings.isEmpty) return;
    widget.runtime.recordFrameTimings(timings);
  }

  @override
  Widget build(BuildContext context) {
    return ScrollReaderV2Viewport(
      runtime: widget.runtime,
      backgroundColor: widget.backgroundColor,
      textColor: widget.textColor,
      style: widget.style,
      onTapUp: widget.onContentTapUp,
      controller: widget.viewportController,
      ttsHighlight: widget.ttsHighlight,
    );
  }
}
