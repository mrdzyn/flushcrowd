/// Core application constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'LooRadar';
  static const String appTagline = 'Find a better loo, anywhere.';

  // Default coordinate fallback (e.g., when location is not yet granted or denied)
  // Defaulting to a central landmark (e.g., Ortigas Center / Manila as seen in canonical UX mock)
  static const double defaultLatitude = 14.5839;
  static const double defaultLongitude = 121.0617;
  static const double defaultZoomLevel = 15.0;

  // GIS & Search parameters
  static const double defaultSearchRadiusMeters = 1500.0;
  static const double maxSearchRadiusMeters =
      10000.0; // Phase 1 hard safety limit: 10 km
  static const int defaultGeohashPrecision = 6; // ~1.2 km precision box
  static const int minRestroomNameLength = 1;
  static const int maxRestroomNameLength = 100;
  static const int maxCommentLength = 500;
  static const int maxReportNotesLength = 1000;

  // Discovery safety caps (Phase 1)
  static const Duration cameraIdleDebounceDuration = Duration(
    milliseconds: 400,
  );
  static const double minViewportZoom =
      12.0; // Zoom threshold below which facilities are not queried
  static const double maxViewportLatitudeSpan = 0.5; // ~55 km max lat span
  static const double maxViewportLongitudeSpan = 0.5; // ~55 km max lng span
  static const int minDiscoveryGeohashPrecision =
      3; // ~156 km x 156 km floor; prevents continental/global prefix scans
  static const int maxGeohashQueryRanges =
      16; // Maximum Firestore range queries per discovery operation
  static const int maxDocumentsPerRangeQuery = 50; // Per-range query limit
  static const int maxCandidateDocuments =
      200; // Hard cap on decoded candidates per discovery operation
  static const int maxDiscoveryResults = 100; // Cap on returned results

  // Firestore Collection Names
  static const String restroomsCollection = 'restrooms';
  static const String ratingsCollection = 'ratings';
  static const String verificationsCollection = 'verifications';
  static const String reportsCollection = 'reports';
  static const String ratingOwnershipCollection = 'ratingOwnership';
  static const String contributionOwnershipCollection = 'contributionOwnership';

  // Support links
  static const String buyMeACoffeeUrl = 'https://buymeacoffee.com/looradar';
  static const String privacyPolicyUrl = 'https://looradar.app/privacy';
}
