import 'dart:async';

/// Per-async-chain flags for source validation.
///
/// Batch source checks must not start interactive browser or captcha flows.
/// Normal reading, debugging, and manual login flows run outside this zone and
/// keep their existing interactive behavior.
class SourceValidationContext {
  SourceValidationContext._();

  static const Object _nonInteractiveKey =
      #inkpageReaderNonInteractiveSourceValidation;

  static bool get isNonInteractive => Zone.current[_nonInteractiveKey] == true;

  static Future<T> runNonInteractive<T>(Future<T> Function() body) {
    return runZoned(
      body,
      zoneValues: const <Object, Object>{_nonInteractiveKey: true},
    );
  }
}

class SourceInteractionBlockedException implements Exception {
  final String message;

  const SourceInteractionBlockedException(this.message);

  @override
  String toString() => message;
}
