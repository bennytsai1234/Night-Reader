typedef TtsSpeechPreparation = Future<bool> Function();
typedef TtsSpeechAction = Future<void> Function();

/// Serializes speak preparation against stop so a stop issued while TTS
/// initialization is pending cannot resurrect the cancelled utterance.
final class TtsSpeechCoordinator {
  int _generation = 0;

  Future<void> speak({
    required TtsSpeechPreparation prepare,
    required TtsSpeechAction speak,
  }) async {
    final generation = ++_generation;
    if (!await prepare()) return;
    if (generation != _generation) return;
    await speak();
  }

  Future<void> stop({required TtsSpeechAction stop}) async {
    _generation += 1;
    await stop();
  }
}
