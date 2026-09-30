/// Boundary for identity and authentication.
/// LooRadar V1 uses Firebase Anonymous Authentication exclusively.
abstract class AuthRepository {
  /// Stream of user ID changes (null if unauthenticated).
  Stream<String?> get authStateChanges;

  /// Returns currently authenticated anonymous UID, or null.
  String? get currentUserId;

  /// Ensures user has an anonymous session. Signs in if needed.
  Future<String> ensureAnonymousSession();
}
