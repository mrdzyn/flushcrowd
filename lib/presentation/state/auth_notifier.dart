import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/repositories/auth_repository.dart';

enum AuthStatus {
  initial,
  authenticating,
  authenticated,
  unauthenticated,
  error,
}

/// State notifier managing anonymous authentication.
class AuthNotifier extends ChangeNotifier {
  final AuthRepository _authRepository;
  StreamSubscription<String?>? _authSubscription;

  AuthStatus _status = AuthStatus.initial;
  String? _userId;
  String? _errorMessage;

  AuthNotifier({required this._authRepository}) {
    _userId = _authRepository.currentUserId;
    if (_userId != null) {
      _status = AuthStatus.authenticated;
    }
    _authSubscription = _authRepository.authStateChanges.listen((uid) {
      if (_userId != uid) {
        _userId = uid;
        if (uid != null) {
          _status = AuthStatus.authenticated;
        } else if (_status == AuthStatus.authenticated) {
          _status = AuthStatus.unauthenticated;
        }
        notifyListeners();
      }
    });
  }

  AuthStatus get status => _status;
  String? get userId => _userId;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated && _userId != null;

  /// Unconditionally ensures a live anonymous session via the underlying repository.
  Future<void> ensureAnonymousSession() async {
    _status = AuthStatus.authenticating;
    _errorMessage = null;
    notifyListeners();

    try {
      _userId = await _authRepository.ensureAnonymousSession();
      _status = AuthStatus.authenticated;
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e.toString();
      _userId = null;
    }
    notifyListeners();
  }

  Future<void> signInAnonymously() => ensureAnonymousSession();

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
