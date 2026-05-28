import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_state.dart';

import 'scroll_reader_v2_viewport.dart';
import 'slide_reader_v2_viewport.dart';

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
  /// Track the last known mode so we only rebuild when scroll ↔ slide changes.
  late ReaderV2Mode _lastMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addTimingsCallback(_handleFrameTimings);
    _lastMode = widget.runtime.state.mode;
    widget.runtime.addListener(_handleRuntimeChanged);
  }

  @override
  void didUpdateWidget(covariant EngineReaderV2Screen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime) {
      oldWidget.runtime.removeListener(_handleRuntimeChanged);
      _lastMode = widget.runtime.state.mode;
      widget.runtime.addListener(_handleRuntimeChanged);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(_handleFrameTimings);
    widget.runtime.removeListener(_handleRuntimeChanged);
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

  void _handleRuntimeChanged() {
    if (!mounted) return;
    // Only rebuild this widget when mode changes (scroll ↔ slide).
    // The child viewports already listen to runtime for content updates.
    final currentMode = widget.runtime.state.mode;
    if (currentMode != _lastMode) {
      _lastMode = currentMode;
      setState(() {});
    }
  }

  void _handleFrameTimings(List<FrameTiming> timings) {
    if (!mounted || timings.isEmpty) return;
    widget.runtime.recordFrameTimings(timings);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.runtime.state;
    final viewport =
        state.mode == ReaderV2Mode.scroll
            ? ScrollReaderV2Viewport(
              runtime: widget.runtime,
              backgroundColor: widget.backgroundColor,
              textColor: widget.textColor,
              style: widget.style,
              onTapUp: widget.onContentTapUp,
              controller: widget.viewportController,
              ttsHighlight: widget.ttsHighlight,
            )
            : SlideReaderV2Viewport(
              runtime: widget.runtime,
              backgroundColor: widget.backgroundColor,
              textColor: widget.textColor,
              style: widget.style,
              onTapUp: widget.onContentTapUp,
              controller: widget.viewportController,
              ttsHighlight: widget.ttsHighlight,
            );
    return viewport;
  }
}
