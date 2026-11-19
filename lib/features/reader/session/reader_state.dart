import 'package:night_reader/features/reader/layout/reader_layout_spec.dart';

import 'reader_location.dart';

enum ReaderLifecycle { cold, ready, unavailable }

class ReaderState {
  const ReaderState({
    required this.lifecycle,
    required this.committedLocation,
    required this.visibleLocation,
    required this.layoutSpec,
    required this.layoutGeneration,
    this.contentGeneration = 0,
    this.unavailableMessage,
  });

  final ReaderLifecycle lifecycle;
  final ReaderLocation committedLocation;
  final ReaderLocation visibleLocation;
  final ReaderLayoutSpec layoutSpec;
  final int layoutGeneration;

  /// Runtime-published semantic document generation.
  ///
  /// This is independent from [layoutGeneration]: content identity may change
  /// without changing the presentation specification.
  final int contentGeneration;
  final String? unavailableMessage;

  bool get hasStableWorld => lifecycle == ReaderLifecycle.ready;

  ReaderState copyWith({
    ReaderLifecycle? lifecycle,
    ReaderLocation? committedLocation,
    ReaderLocation? visibleLocation,
    ReaderLayoutSpec? layoutSpec,
    int? layoutGeneration,
    int? contentGeneration,
    String? unavailableMessage,
    bool clearUnavailableMessage = false,
  }) {
    return ReaderState(
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
