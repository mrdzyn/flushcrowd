/// Controlled access types for restrooms.
enum AccessType {
  free('free'),
  paid('paid'),
  customerOnly('customer_only'),
  keyRequired('key_required');

  final String value;
  const AccessType(this.value);

  static AccessType fromString(String? val) {
    if (val == null) return AccessType.free;
    for (final e in AccessType.values) {
      if (e.value.toLowerCase() == val.toLowerCase() ||
          e.name.toLowerCase() == val.toLowerCase()) {
        return e;
      }
    }
    return AccessType.free;
  }

  String get label {
    switch (this) {
      case AccessType.free:
        return 'Free';
      case AccessType.paid:
        return 'Paid';
      case AccessType.customerOnly:
        return 'Customer Only';
      case AccessType.keyRequired:
        return 'Key Required';
    }
  }
}

/// Lifecycle status for restroom records.
enum RestroomStatus {
  active('active'),
  unverified('unverified'),
  flagged('flagged'),
  temporarilyUnavailable('temporarily_unavailable'),
  removed('removed');

  final String value;
  const RestroomStatus(this.value);

  static RestroomStatus fromString(String? val) {
    if (val == null) return RestroomStatus.active;
    for (final e in RestroomStatus.values) {
      if (e.value.toLowerCase() == val.toLowerCase() ||
          e.name.toLowerCase() == val.toLowerCase()) {
        return e;
      }
    }
    return RestroomStatus.active;
  }
}

/// Verification results submitted by community members.
enum VerificationResult {
  confirmed('confirmed'),
  notFound('not_found'),
  temporarilyUnavailable('temporarily_unavailable');

  final String value;
  const VerificationResult(this.value);

  static VerificationResult fromString(String? val) {
    if (val == null) return VerificationResult.confirmed;
    for (final e in VerificationResult.values) {
      if (e.value.toLowerCase() == val.toLowerCase() ||
          e.name.toLowerCase() == val.toLowerCase()) {
        return e;
      }
    }
    return VerificationResult.confirmed;
  }
}

/// Reasons for submitting a facility report.
enum ReportReason {
  duplicate('duplicate'),
  permanentlyClosed('permanently_closed'),
  wrongLocation('wrong_location'),
  inaccurateDetails('inaccurate_details'),
  inappropriateContent('inappropriate_content'),
  other('other');

  final String value;
  const ReportReason(this.value);

  static ReportReason fromString(String? val) {
    if (val == null) return ReportReason.other;
    for (final e in ReportReason.values) {
      if (e.value.toLowerCase() == val.toLowerCase() ||
          e.name.toLowerCase() == val.toLowerCase()) {
        return e;
      }
    }
    return ReportReason.other;
  }
}

/// Moderation review status for user reports.
enum ReportStatus {
  pending('pending'),
  reviewed('reviewed'),
  resolved('resolved');

  final String value;
  const ReportStatus(this.value);

  static ReportStatus fromString(String? val) {
    if (val == null) return ReportStatus.pending;
    for (final e in ReportStatus.values) {
      if (e.value.toLowerCase() == val.toLowerCase() ||
          e.name.toLowerCase() == val.toLowerCase()) {
        return e;
      }
    }
    return ReportStatus.pending;
  }
}

/// Foreground device location permission states.
enum LocationPermissionState {
  notRequested,
  granted,
  denied,
  permanentlyDenied,
  serviceDisabled;

  bool get isGranted => this == LocationPermissionState.granted;
  bool get isDenied => this == LocationPermissionState.denied;
  bool get isPermanentlyDenied =>
      this == LocationPermissionState.permanentlyDenied;
  bool get isServiceDisabled => this == LocationPermissionState.serviceDisabled;
}
