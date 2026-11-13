/// Prepares reader text for system TTS without changing the displayed source
/// text or the UTF-16 offsets used for sentence highlighting.
final class ReaderV2TtsSpeechText {
  const ReaderV2TtsSpeechText._();

  // Chinese ellipses (… / ⋯) and runs of three or more ASCII/fullwidth dots.
  static final RegExp _ellipsis = RegExp(r'(?:[.．]{3,}|[…⋯]+)');
  static final RegExp _onlyEllipses = RegExp(
    r'^(?:\s*(?:[.．]{3,}|[…⋯]+)\s*)+$',
  );

  static String prepare(String text) {
    // A punctuation-only segment must not become a TTS request for a comma.
    // Otherwise some engines read the punctuation aloud or never finish it.
    if (_onlyEllipses.hasMatch(text)) return '';
    // Keep a natural speech pause while avoiding spoken "dot, dot, dot".
    return text.replaceAll(_ellipsis, '，');
  }
}
