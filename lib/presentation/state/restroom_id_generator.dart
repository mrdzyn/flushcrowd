import 'dart:math';

/// Interface for generating canonical, stable restroom document IDs.
///
/// Designed to be allocated once at the application/presentation layer
/// upon successful validation and retained across submission attempts.
abstract interface class RestroomIdGenerator {
  String generate();
}

/// Production implementation generating 20-character alphanumeric IDs
/// matching Cloud Firestore document auto-ID conventions without network requests.
class DefaultRestroomIdGenerator implements RestroomIdGenerator {
  static const String _autoIdAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  final Random _random;

  DefaultRestroomIdGenerator([Random? random])
    : _random = random ?? Random.secure();

  @override
  String generate() {
    final buffer = StringBuffer();
    for (var i = 0; i < 20; i++) {
      buffer.write(_autoIdAlphabet[_random.nextInt(_autoIdAlphabet.length)]);
    }
    return buffer.toString();
  }
}
