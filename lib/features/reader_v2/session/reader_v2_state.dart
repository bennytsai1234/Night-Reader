import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

import 'reader_v2_location.dart';

enum ReaderV2Lifecycle { cold, ready, unavailable }

class ReaderV2State {
  const ReaderV2State({
    required this.lifecycle,
    required this.committedLocation,
    required this.visibleLocation,
    required this.layoutSpec,
    required this.layoutGeneration,
    this.contentGeneration = 0,
    this.unavailableMessage,
  });

  final ReaderV2Lifecycle lifecycle;
  final ReaderV2Location committedLocation;
  final ReaderV2Location visibleLocation;
  final ReaderV2LayoutSpec layoutSpec;
  final int layoutGeneration;

  /// Runtime-published semantic document generation.
  ///
  /// This is independent from [layoutGeneration]: content identity may change
  /// without changing the presentation specification.
  final int contentGeneration;
  final String? unavailableMessage;

  bool get hasStableWorld => lifecycle == ReaderV2Lifecycle.ready;

  ReaderV2State copyWith({
    ReaderV2Lifecycle? lifecycle,
    ReaderV2Location? committedLocation,
    ReaderV2Location? visibleLocation,
    ReaderV2LayoutSpec? layoutSpec,
    int? layoutGeneration,
    int? contentGeneration,
    String? unavailableMessage,
    bool clearUnavailableMessage = false,
  }) {
    return ReaderV2State(
      lifecycle: lifecycle ?? this.lifecycle,
      committedLocation: committedLocation ?? this.committedLocation,
      visibleLocation: visibleLocation ?? this.visibleLocation,
      layoutSpec: layoutSpec ?? this.layoutSpec,
      layoutGeneration: layoutGeneration ?? this.layoutGeneration,
      contentGeneration: contentGeneration ?? this.contentGeneration,
      unavailableMessage: clearUnavailableMessage
          ? null
          : (unavailableMessage ?? this.unavailableMessage),
    );
  }
}
