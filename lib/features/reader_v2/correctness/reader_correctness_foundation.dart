/// Pure contracts shared by the host correctness tests and Android tests.
///
/// This file deliberately has no Flutter dependency.  The pixel decoder only
/// consumes the measured ink width of each rendered row; it never receives
/// source text, Reader state, or a widget reference.

const int readerCorrectnessFixtureSeed = 9132026;
const int readerCorrectnessChapterCount = 121;

/// Logical viewport measured from the NightReader_120Hz AVD on 2026-09-14:
/// `adb shell wm size` = 1280x2856 and `wm density` = 480, so Flutter's
/// devicePixelRatio is 3.0 and the app viewport is 426.6667 x 952 logical px.
/// The same value is used by host tests so topology measurements are portable.
const double readerCorrectnessViewportWidth = 1280 / 3;
const double readerCorrectnessViewportHeight = 2856 / 3;

const String readerCorrectnessFixturePath =
    'test/fixtures/reader_correctness_book.txt';

enum ReaderTopologyAnchor {
  bookStart,
  shortPreface,
  veryShortChapterOne,
  veryShortChapterTwo,
  firstRegularChapter,
  veryLongChapter,
  exactBoundaryChapter,
  distantChapter,
  penultimateChapterTail,
  finalChapterBottom,
}

final class ReaderTopologyLocation {
  const ReaderTopologyLocation({
    required this.anchor,
    required this.chapterIndex,
    required this.paragraphIndex,
  });

  final ReaderTopologyAnchor anchor;
  final int chapterIndex;
  final int paragraphIndex;
}

/// The binary ink profile is rendered as one visual row per bit.  `墨` has
/// ink in the default Flutter test font while U+2060 is retained as a layout
/// row but has no painted pixels. Ordinary newlines separate the short profile rows;
/// that is intentional because Reader's normalizer preserves them as separate
/// paragraphs and Flutter's host text engine handles them consistently.
final class ReaderInkProfile {
  const ReaderInkProfile._({
    required this.chapterIndex,
    required this.paragraphIndex,
    required this.bits,
  });

  final int chapterIndex;
  final int paragraphIndex;
  final List<bool> bits;

  int get rowCount => bits.length;

  String get renderBand => bits.map((bit) => bit ? '墨' : '\u2060').join('\n');

  List<int> get expectedInkWidths => [for (final bit in bits) bit ? 1 : 0];
}

/// Encode a paragraph identity into a fixed-width sentinel + payload + parity
/// profile.  Seven bits per coordinate cover the fixture's 0..120 chapters
/// and 0..127 paragraphs while keeping the band short enough for topology.
ReaderInkProfile encodeReaderInkProfile({
  required int chapterIndex,
  required int paragraphIndex,
}) {
  if (chapterIndex < 0 || chapterIndex > 127) {
    throw RangeError.range(chapterIndex, 0, 127, 'chapterIndex');
  }
  if (paragraphIndex < 0 || paragraphIndex > 127) {
    throw RangeError.range(paragraphIndex, 0, 127, 'paragraphIndex');
  }

  final bits = <bool>[
    true,
    false,
    true,
    false,
    for (var bit = 6; bit >= 0; bit -= 1) ((chapterIndex >> bit) & 1) == 1,
    for (var bit = 6; bit >= 0; bit -= 1) ((paragraphIndex >> bit) & 1) == 1,
  ];
  final ones = bits.take(18).where((bit) => bit).length;
  bits.add(ones.isOdd);
  return ReaderInkProfile._(
    chapterIndex: chapterIndex,
    paragraphIndex: paragraphIndex,
    bits: List<bool>.unmodifiable(bits),
  );
}

/// Decode measured per-row ink widths.  Any positive width means "ink";
/// zero means "no ink".  The caller may pass int, double, or other numeric
/// pixel measurements, but no textual or Reader metadata is accepted.
({int chapterIndex, int paragraphIndex}) decodeReaderInkProfile(
  Iterable<num> inkWidths,
) {
  final bits = inkWidths.map((width) => width > 0).toList(growable: false);
  if (bits.length != 19 ||
      bits[0] != true ||
      bits[1] != false ||
      bits[2] != true ||
      bits[3] != false) {
    throw const FormatException('Reader ink profile sentinel/length mismatch');
  }

  var chapterIndex = 0;
  for (var bit = 0; bit < 7; bit += 1) {
    chapterIndex = (chapterIndex << 1) | (bits[4 + bit] ? 1 : 0);
  }
  var paragraphIndex = 0;
  for (var bit = 0; bit < 7; bit += 1) {
    paragraphIndex = (paragraphIndex << 1) | (bits[11 + bit] ? 1 : 0);
  }
  final ones = bits.take(18).where((bit) => bit).length;
  if (bits[18] != ones.isOdd) {
    throw const FormatException('Reader ink profile parity mismatch');
  }
  return (chapterIndex: chapterIndex, paragraphIndex: paragraphIndex);
}

/// Checks the complete set of paragraph identities and intentionally rejects
/// duplicate identities.  It is pure so the generator and both test layers
/// can use exactly the same collision rule.
void assertUniqueReaderInkProfiles(
  Iterable<({int chapterIndex, int paragraphIndex})> coordinates,
) {
  final seen = <String>{};
  for (final coordinate in coordinates) {
    final key = '${coordinate.chapterIndex}:${coordinate.paragraphIndex}';
    if (!seen.add(key)) {
      throw StateError('Reader ink profile collision: $key');
    }
  }
}

enum ReaderOpDirection { forward, backward, none }

/// Stable, file-safe identifier shared by host manifests and Android replay.
String readerCaseId({
  required String layer,
  required String opSequence,
  required String position,
  required String state,
  required int seed,
}) {
  String token(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    if (normalized.isEmpty) throw ArgumentError.value(value, 'token');
    return normalized;
  }

  if (seed < 0) throw ArgumentError.value(seed, 'seed');
  return 'C-${token(layer)}-${token(opSequence)}-${token(position)}-${token(state)}-$seed';
}

final class ReaderFixtureChapter {
  const ReaderFixtureChapter({
    required this.index,
    required this.title,
    required this.paragraphs,
  });

  final int index;
  final String title;
  final List<String> paragraphs;

  String get content => paragraphs.join('\n\n');
}

final class ReaderCorrectnessFixture {
  const ReaderCorrectnessFixture._(this.chapters);

  final List<ReaderFixtureChapter> chapters;

  ReaderTopologyLocation topologyAnchor(ReaderTopologyAnchor anchor) {
    final location = switch (anchor) {
      ReaderTopologyAnchor.bookStart => (chapterIndex: 0, paragraphIndex: 0),
      ReaderTopologyAnchor.shortPreface => (chapterIndex: 0, paragraphIndex: 0),
      ReaderTopologyAnchor.veryShortChapterOne => (
        chapterIndex: 1,
        paragraphIndex: 0,
      ),
      ReaderTopologyAnchor.veryShortChapterTwo => (
        chapterIndex: 2,
        paragraphIndex: 0,
      ),
      ReaderTopologyAnchor.firstRegularChapter => (
        chapterIndex: 3,
        paragraphIndex: 0,
      ),
      ReaderTopologyAnchor.veryLongChapter => (
        chapterIndex: 60,
        paragraphIndex: 41,
      ),
      ReaderTopologyAnchor.exactBoundaryChapter => (
        chapterIndex: 61,
        paragraphIndex: 0,
      ),
      ReaderTopologyAnchor.distantChapter => (
        chapterIndex: 90,
        paragraphIndex: 0,
      ),
      ReaderTopologyAnchor.penultimateChapterTail => (
        chapterIndex: 119,
        paragraphIndex: 4,
      ),
      ReaderTopologyAnchor.finalChapterBottom => (
        chapterIndex: 120,
        paragraphIndex: 4,
      ),
    };
    return ReaderTopologyLocation(
      anchor: anchor,
      chapterIndex: location.chapterIndex,
      paragraphIndex: location.paragraphIndex,
    );
  }

  static ReaderCorrectnessFixture generate({
    int seed = readerCorrectnessFixtureSeed,
  }) {
    final random = _DeterministicRandom(seed);
    final chapters = <ReaderFixtureChapter>[
      ReaderFixtureChapter(
        index: 0,
        title: '前言',
        paragraphs: <String>[
          _paragraph(
            chapterIndex: 0,
            paragraphIndex: 0,
            random: random,
            short: true,
          ),
        ],
      ),
    ];
    for (var index = 1; index < readerCorrectnessChapterCount; index += 1) {
      final paragraphCount = switch (index) {
        1 || 2 => 1,
        60 => 42,
        61 => 8,
        _ => 5,
      };
      chapters.add(
        ReaderFixtureChapter(
          index: index,
          title: '第${_chineseNumber(index)}章',
          paragraphs: [
            for (
              var paragraphIndex = 0;
              paragraphIndex < paragraphCount;
              paragraphIndex += 1
            )
              _paragraph(
                chapterIndex: index,
                paragraphIndex: paragraphIndex,
                random: random,
                short: index == 1 || index == 2,
              ),
          ],
        ),
      );
    }
    assertUniqueReaderInkProfiles(
      chapters.expand(
        (chapter) => [
          for (
            var paragraphIndex = 0;
            paragraphIndex < chapter.paragraphs.length;
            paragraphIndex += 1
          )
            (chapterIndex: chapter.index, paragraphIndex: paragraphIndex),
        ],
      ),
    );
    return ReaderCorrectnessFixture._(
      List<ReaderFixtureChapter>.unmodifiable(chapters),
    );
  }

  String serialize() {
    final lines = <String>[];
    for (final chapter in chapters) {
      if (chapter.index > 0) lines.add(chapter.title);
      lines.addAll(chapter.paragraphs);
      lines.add('');
    }
    return '${lines.join('\n').trimRight()}\n';
  }

  static String _paragraph({
    required int chapterIndex,
    required int paragraphIndex,
    required _DeterministicRandom random,
    required bool short,
  }) {
    final profile = encodeReaderInkProfile(
      chapterIndex: chapterIndex,
      paragraphIndex: paragraphIndex,
    );
    final identifier =
        'P${chapterIndex.toString().padLeft(3, '0')}-${paragraphIndex.toString().padLeft(3, '0')}';
    if (short) return '$identifier：短。 ${profile.renderBand}';
    final repeats = 2;
    final prose = StringBuffer('$identifier：');
    const vocabulary = <String>[
      '夜色沿著窗紙慢慢沉下來，墨香與遠處的風聲交疊成安靜的讀頁節拍。',
      '人物在燈影之外停步，等候下一個轉折，也讓每一行文字保留清楚的邊界。',
      '這段固定文字只服務於可重現的排版拓撲，內容本身不承擔產品語意。',
      '讀者可以從章節與段落標記辨認目前畫面，而不必相信 Reader 自己的回報。',
    ];
    for (var i = 0; i < repeats; i += 1) {
      prose.write(vocabulary[random.nextInt(vocabulary.length)]);
    }
    if (chapterIndex == 61 && paragraphIndex == 0) {
      // The boundary anchor is intentionally tuned against the measured
      // NightReader_120Hz logical viewport. This adds nineteen line advances
      // and leaves only the renderer's two-pixel rounding residue from 9x
      // 952 logical px.
      prose.write(List<String>.filled(420, '界').join());
    }
    prose.write(' ${profile.renderBand}');
    return prose.toString();
  }
}

String _chineseNumber(int value) {
  const digits = <String>['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
  if (value < 10) return digits[value];
  if (value < 20) return '十${value == 10 ? '' : digits[value - 10]}';
  if (value < 100)
    return '${digits[value ~/ 10]}十${value % 10 == 0 ? '' : digits[value % 10]}';
  if (value < 1000)
    return '${digits[value ~/ 100]}百${value % 100 == 0 ? '' : _chineseNumber(value % 100)}';
  throw ArgumentError.value(
    value,
    'value',
    'fixture supports values below 1000',
  );
}

final class _DeterministicRandom {
  _DeterministicRandom(int seed) : _state = seed & 0x7fffffff;

  int _state;

  int nextInt(int max) {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state % max;
  }
}
