/// Core exceptions thrown across FlushCrowd layers.
class AppException implements Exception {
  final String message;
  final String? code;

  const AppException(this.message, [this.code]);

  @override
  String toString() => 'AppException: $message (code: $code)';
}

class LocationException extends AppException {
  const LocationException(super.message, [super.code]);
}

class LocationPermissionDeniedException extends LocationException {
  const LocationPermissionDeniedException([
    super.message = 'Location permission denied by user.',
  ]);
}

class LocationPermissionPermanentlyDeniedException extends LocationException {
  const LocationPermissionPermanentlyDeniedException([
    super.message =
        'Location permission permanently denied. Enable in device settings.',
  ]);
}

class LocationServiceDisabledException extends LocationException {
  const LocationServiceDisabledException([
    super.message = 'Location services are disabled on device.',
  ]);
}

class GisException extends AppException {
  const GisException(super.message, [super.code]);
}

class InvalidCoordinatesException extends GisException {
  const InvalidCoordinatesException(super.message);
}

class InvalidRadiusException extends GisException {
  const InvalidRadiusException(super.message);
}

class ViewportTooLargeException extends GisException {
  const ViewportTooLargeException(super.message);
}

class RepositoryException extends AppException {
  const RepositoryException(super.message, [super.code]);
}

class AuthException extends AppException {
  const AuthException(super.message, [super.code]);
}

class RestroomNotFoundException extends AppException {
  const RestroomNotFoundException([
    super.message = 'Restroom facility not found.',
  ]);
}

class UnauthenticatedException extends AuthException {
  const UnauthenticatedException([
    super.message = 'Authentication required to perform this action.',
    super.code = 'unauthenticated',
  ]);
}

class SubmissionInvariantException extends RepositoryException {
  const SubmissionInvariantException([
    super.message =
        'Submission invariant violation: atomic record state is inconsistent.',
    super.code = 'submission-invariant-violation',
  ]);
}
