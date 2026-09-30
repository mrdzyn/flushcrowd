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

  AuthStatus _status = AuthStatus.initial;
  String? _userId;
  String? _errorMessage;

  AuthNotifier({required this._authRepository}) {
    _userId = _authRepository.currentUserId;
    if (_userId != null) {
      _status = AuthStatus.authenticated;
    }
  }

  AuthStatus get status => _status;
  String? get userId => _userId;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  Future<void> signInAnonymously() async {
    _status = AuthStatus.authenticating;
    _errorMessage = null;
    notifyListeners();

    try {
      _userId = await _authRepository.ensureAnonymousSession();
      _status = AuthStatus.authenticated;
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }
}
