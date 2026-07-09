import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';

final class AdmissionController extends ChangeNotifier {
  AdmissionController({
    required this.documentIndex,
    this.guaranteedWindow = 6000,
  });

  final DocumentIndex documentIndex;
  final double guaranteedWindow;
  StreamSubscription<BlockReady>? _subscription;
  double _latestForwardLead = double.infinity;
  double _latestBackwardLead = double.infinity;

  double get latestForwardLead => _latestForwardLead;
  double get latestBackwardLead => _latestBackwardLead;

  void attach(Stream<BlockReady> completed) {
    _subscription?.cancel();
    _subscription = completed.listen((ready) {
      documentIndex.admit(ready.key, ready.metrics);
      notifyListeners();
    });
  }

  bool canAdmitOutsideVisible({
    required BlockKey key,
    required double visibleTop,
    required double visibleBottom,
    required double cacheExtent,
  }) {
    final top = documentIndex.topOf(key);
    final bottom = documentIndex.bottomOf(key);
    if (top == null || bottom == null) return true;
    final safeTop = visibleTop - cacheExtent;
    final safeBottom = visibleBottom + cacheExtent;
    final outside = bottom <= safeTop || top >= safeBottom;
    assert(
      outside,
      'I2: admitted block must enter outside visible+cacheExtent.',
    );
    return outside;
  }

  void updateLead({
    required double viewportTop,
    required double viewportBottom,
  }) {
    _latestForwardLead = documentIndex.afterExtent - viewportBottom;
    _latestBackwardLead = documentIndex.beforeExtent + viewportTop;
    assert(
      _latestForwardLead >= -guaranteedWindow &&
          _latestBackwardLead >= -guaranteedWindow,
      'I5: admitted lead distance fell behind the guaranteed window.',
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
