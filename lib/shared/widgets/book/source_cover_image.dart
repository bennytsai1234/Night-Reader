import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:night_reader/core/storage/source_cover_loader.dart';

/// 書源的網路封面（[SourceCoverLoader]）：照書的書源 [origin] 抓 [url]。
@immutable
class SourceCoverImage extends ImageProvider<SourceCoverImage> {
  const SourceCoverImage(this.url, this.origin);

  final String url;
  final String origin;

  @override
  Future<SourceCoverImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<SourceCoverImage>(this);

  @override
  ImageStreamCompleter loadImage(
    SourceCoverImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: url,
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await SourceCoverLoader.load(url, origin);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is SourceCoverImage && other.url == url && other.origin == origin;

  @override
  int get hashCode => Object.hash(url, origin);
}
