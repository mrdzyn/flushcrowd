import 'package:equatable/equatable.dart';

/// Base Failure representation for UI state and error boundaries.
abstract class Failure extends Equatable {
  final String message;
  final String? code;

  const Failure(this.message, [this.code]);

  @override
  List<Object?> get props => [message, code];
}

class LocationFailure extends Failure {
  const LocationFailure(super.message, [super.code]);
}

class PermissionDeniedFailure extends LocationFailure {
  const PermissionDeniedFailure([
    super.message = 'Location access is required to show nearby restrooms.',
  ]);
}

class PermissionPermanentlyDeniedFailure extends LocationFailure {
  const PermissionPermanentlyDeniedFailure([
    super.message = 'Location permission is permanently denied. Please enable it in Settings.',
  ]);
}

class LocationServiceDisabledFailure extends LocationFailure {
  const LocationServiceDisabledFailure([
    super.message =
        'Device location service is turned off. Please turn on GPS.',
  ]);
}

class GisFailure extends Failure {
  const GisFailure(super.message, [super.code]);
}

class InvalidRadiusFailure extends GisFailure {
  const InvalidRadiusFailure([
    super.message =
        'The requested search radius is invalid or exceeds maximum limit.',
  ]);
}

class ViewportTooLargeFailure extends GisFailure {
  const ViewportTooLargeFailure([
    super.message =
        'The visible area is too large. Zoom in to discover restrooms.',
  ]);
}

class RepositoryFailure extends Failure {
  const RepositoryFailure([
    super.message = 'Failed to load restroom data.',
    super.code,
  ]);
}

class AuthFailure extends Failure {
  const AuthFailure(super.message, [super.code]);
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = 'An unexpected server error occurred.']);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Network connection unavailable.']);
}
