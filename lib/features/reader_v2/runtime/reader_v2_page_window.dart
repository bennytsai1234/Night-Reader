import 'package:reader/features/reader_v2/render/reader_v2_render_page.dart';

class ReaderV2PageWindow {
  const ReaderV2PageWindow({
    required this.prev,
    required this.current,
    required this.next,
    this.lookAhead = const <ReaderV2RenderPage>[],
  });

  final ReaderV2RenderPage? prev;
  final ReaderV2RenderPage current;
  final ReaderV2RenderPage? next;
  final List<ReaderV2RenderPage> lookAhead;

  List<ReaderV2RenderPage> get pages => <ReaderV2RenderPage>[
    if (prev != null) prev!,
    current,
    if (next != null) next!,
    ...lookAhead,
  ];

  Set<int> get chapterIndexes => pages.map((page) => page.chapterIndex).toSet();

  ReaderV2PageWindow copyWith({
    ReaderV2RenderPage? prev,
    bool clearPrev = false,
    ReaderV2RenderPage? current,
    ReaderV2RenderPage? next,
    bool clearNext = false,
    List<ReaderV2RenderPage>? lookAhead,
  }) {
    return ReaderV2PageWindow(
      prev: clearPrev ? null : (prev ?? this.prev),
      current: current ?? this.current,
      next: clearNext ? null : (next ?? this.next),
      lookAhead: lookAhead ?? this.lookAhead,
    );
  }

  List<ReaderV2RenderPage> get paintForwardPages => <ReaderV2RenderPage>[
    current,
    if (next != null) next!,
    ...lookAhead,
  ];
}
