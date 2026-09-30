import 'package:firebase_auth/firebase_auth.dart';

import '../../core/errors/exceptions.dart';
import '../../domain/repositories/auth_repository.dart';

/// Firebase Anonymous Authentication repository implementation.
class FirebaseAuthRepositoryImpl implements AuthRepository {
  final FirebaseAuth _firebaseAuth;

  FirebaseAuthRepositoryImpl({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  @override
  Stream<String?> get authStateChanges =>
      _firebaseAuth.authStateChanges().map((user) => user?.uid);

  @override
  String? get currentUserId => _firebaseAuth.currentUser?.uid;

  @override
  Future<String> ensureAnonymousSession() async {
    try {
      final currentUser = _firebaseAuth.currentUser;
      if (currentUser != null) {
        return currentUser.uid;
      }

      final userCredential = await _firebaseAuth.signInAnonymously();
      final user = userCredential.user;
      if (user == null) {
        throw const AuthException('Anonymous sign-in returned no user.');
      }
      return user.uid;
    } catch (e) {
      throw AuthException('Failed to establish anonymous session: $e');
    }
  }
}

/// In-memory AuthRepository test double for unit and widget testing.
class InMemoryAuthRepository implements AuthRepository {
  String? _uid;

  InMemoryAuthRepository({String? initialUid = 'test_anon_uid_123'})
    : _uid = initialUid;

  @override
  Stream<String?> get authStateChanges => Stream.value(_uid);

  @override
  String? get currentUserId => _uid;

  @override
  Future<String> ensureAnonymousSession() async {
    _uid ??= 'test_anon_uid_123';
    return _uid!;
  }
}
