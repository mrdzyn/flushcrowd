import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flushcrowd/core/errors/exceptions.dart';
import 'package:flushcrowd/domain/repositories/auth_repository.dart';
import 'package:flushcrowd/presentation/state/auth_notifier.dart';

class _TestAuthRepository implements AuthRepository {
  final StreamController<String?> _controller =
      StreamController<String?>.broadcast();
  String? _uid;
  bool shouldThrow = false;

  _TestAuthRepository({String? initialUid}) : _uid = initialUid;

  @override
  Stream<String?> get authStateChanges => _controller.stream;

  @override
  String? get currentUserId => _uid;

  void setUid(String? uid) {
    _uid = uid;
    _controller.add(uid);
  }

  @override
  Future<String> ensureAnonymousSession() async {
    if (shouldThrow) {
      throw const RepositoryException(
        'Simulated auth timeout',
        'network-error',
      );
    }
    _uid = _uid ?? 'generated_anon_uid_456';
    _controller.add(_uid);
    return _uid!;
  }
}

void main() {
  group('AuthNotifier', () {
    test(
      'Initializes as unauthenticated when repository currentUserId is null',
      () {
        final repo = _TestAuthRepository(initialUid: null);
        final notifier = AuthNotifier(authRepository: repo);

        expect(notifier.status, equals(AuthStatus.initial));
        expect(notifier.userId, isNull);
        expect(notifier.isAuthenticated, isFalse);
      },
    );

    test(
      'Initializes as authenticated when repository currentUserId is present',
      () {
        final repo = _TestAuthRepository(initialUid: 'initial_user_uid');
        final notifier = AuthNotifier(authRepository: repo);

        expect(notifier.status, equals(AuthStatus.authenticated));
        expect(notifier.userId, equals('initial_user_uid'));
        expect(notifier.isAuthenticated, isTrue);
      },
    );

    test(
      'ensureAnonymousSession establishes session and notifies listeners',
      () async {
        final repo = _TestAuthRepository(initialUid: null);
        final notifier = AuthNotifier(authRepository: repo);

        var notificationCount = 0;
        notifier.addListener(() => notificationCount++);

        await notifier.ensureAnonymousSession();

        expect(notifier.status, equals(AuthStatus.authenticated));
        expect(notifier.userId, equals('generated_anon_uid_456'));
        expect(notifier.isAuthenticated, isTrue);
        expect(
          notificationCount,
          greaterThanOrEqualTo(2),
        ); // authenticating + authenticated
      },
    );

    test(
      'ensureAnonymousSession clears userId on error and sets status error',
      () async {
        final repo = _TestAuthRepository(initialUid: 'prior_uid');
        final notifier = AuthNotifier(authRepository: repo);
        expect(notifier.isAuthenticated, isTrue);

        repo.shouldThrow = true;
        await notifier.ensureAnonymousSession();

        expect(notifier.status, equals(AuthStatus.error));
        expect(notifier.userId, isNull);
        expect(notifier.isAuthenticated, isFalse);
        expect(notifier.errorMessage, contains('Simulated auth timeout'));
      },
    );

    test(
      'Listens to authStateChanges and updates status when stream emits',
      () async {
        final repo = _TestAuthRepository(initialUid: 'uid_1');
        final notifier = AuthNotifier(authRepository: repo);
        expect(notifier.isAuthenticated, isTrue);

        repo.setUid(null);
        await pumpEventQueue();

        expect(notifier.status, equals(AuthStatus.unauthenticated));
        expect(notifier.userId, isNull);
        expect(notifier.isAuthenticated, isFalse);

        repo.setUid('uid_2');
        await pumpEventQueue();

        expect(notifier.status, equals(AuthStatus.authenticated));
        expect(notifier.userId, equals('uid_2'));
        expect(notifier.isAuthenticated, isTrue);
      },
    );

    test('Re-establishes anonymous session when underlying repository UID becomes null', () async {
      final repo = _TestAuthRepository(initialUid: 'uid_before_expiry');
      final notifier = AuthNotifier(authRepository: repo);
      expect(notifier.isAuthenticated, isTrue);

      // Simulate expired or signed-out session
      repo.setUid(null);
      await pumpEventQueue();
      expect(notifier.isAuthenticated, isFalse);

      // ensureAnonymousSession establishes fresh session
      await notifier.ensureAnonymousSession();
      expect(notifier.status, equals(AuthStatus.authenticated));
      expect(notifier.userId, equals('generated_anon_uid_456'));
      expect(notifier.isAuthenticated, isTrue);
    });
  });
}
