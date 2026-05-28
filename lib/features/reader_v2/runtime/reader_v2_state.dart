import 'package:night_reader/features/reader_v2/render/reader_v2_render_page.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

import 'reader_v2_location.dart';
import 'reader_v2_page_window.dart';

enum ReaderV2Mode { scroll, slide }

enum ReaderV2Phase {
  cold,
  loading,
  layingOut,
  restoring,
  ready,
  switchingMode,
  error,
}

class ReaderV2State {
  const ReaderV2State({
    required this.mode,
    required this.phase,
    required this.committedLocation,
    required this.visibleLocation,
    required this.layoutSpec,
    required this.layoutGeneration,
    this.pageWindow,
    this.currentSlidePage,
    this.errorMessage,
  });

  final ReaderV2Mode mode;
  final ReaderV2Phase phase;
  final ReaderV2Location committedLocation;
  final ReaderV2Location visibleLocation;
  final ReaderV2LayoutSpec layoutSpec;
  final int layoutGeneration;
  final ReaderV2PageWindow? pageWindow;
  final ReaderV2RenderPage? currentSlidePage;
  final String? errorMessage;

  ReaderV2State copyWith({
    ReaderV2Mode? mode,
    ReaderV2Phase? phase,
    ReaderV2Location? committedLocation,
    ReaderV2Location? visibleLocation,
    ReaderV2LayoutSpec? layoutSpec,
    int? layoutGeneration,
    ReaderV2PageWindow? pageWindow,
    bool clearPageWindow = false,
    ReaderV2RenderPage? currentSlidePage,
    bool clearCurrentSlidePage = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ReaderV2State(
      mode: mode ?? this.mode,
      phase: phase ?? this.phase,
      committedLocation: committedLocation ?? this.committedLocation,
      visibleLocation: visibleLocation ?? this.visibleLocation,
      layoutSpec: layoutSpec ?? this.layoutSpec,
      layoutGeneration: layoutGeneration ?? this.layoutGeneration,
      pageWindow: clearPageWindow ? null : (pageWindow ?? this.pageWindow),
      currentSlidePage:
          clearCurrentSlidePage
              ? null
              : (currentSlidePage ?? this.currentSlidePage),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
