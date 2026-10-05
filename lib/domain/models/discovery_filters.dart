import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'restroom.dart';

/// Immutable filter criteria applied locally over discovered restroom results.
///
/// Semantics:
/// - Within a multi-value category (e.g. [accessTypes], [genderTypes]): OR logic.
/// - Across categories: AND logic.
/// - Boolean amenity flags: if true, requires the corresponding amenity (AND).
/// - [minRating]: requires [restroom.averageRating] >= [minRating].
/// - [recentlyVerifiedOnly]: requires restroom to have [lastVerifiedAt] within [recentVerificationThreshold].
class DiscoveryFilters extends Equatable {
  final Set<AccessType> accessTypes;
  final Set<GenderTypeFilter> genderTypes;
  final bool pwdAccessibleOnly;
  final bool babyChangingOnly;
  final bool bidetOnly;
  final bool toiletPaperOnly;
  final bool soapOnly;
  final bool handDryerOnly;
  final bool recentlyVerifiedOnly;
  final double minRating;

  /// Default threshold for recent verification: 90 days.
  static const Duration recentVerificationThreshold = Duration(days: 90);

  const DiscoveryFilters({
    this.accessTypes = const {},
    this.genderTypes = const {},
    this.pwdAccessibleOnly = false,
    this.babyChangingOnly = false,
    this.bidetOnly = false,
    this.toiletPaperOnly = false,
    this.soapOnly = false,
    this.handDryerOnly = false,
    this.recentlyVerifiedOnly = false,
    this.minRating = 0.0,
  });

  /// An empty/unfiltered filter set.
  static const DiscoveryFilters empty = DiscoveryFilters();

  /// Whether any filter criteria are currently active.
  bool get isActive {
    return accessTypes.isNotEmpty ||
        genderTypes.isNotEmpty ||
        pwdAccessibleOnly ||
        babyChangingOnly ||
        bidetOnly ||
        toiletPaperOnly ||
        soapOnly ||
        handDryerOnly ||
        recentlyVerifiedOnly ||
        minRating > 0.0;
  }

  /// Number of active filter constraints.
  int get activeFilterCount {
    int count = 0;
    if (accessTypes.isNotEmpty) count += accessTypes.length;
    if (genderTypes.isNotEmpty) count += genderTypes.length;
    if (pwdAccessibleOnly) count++;
    if (babyChangingOnly) count++;
    if (bidetOnly) count++;
    if (toiletPaperOnly) count++;
    if (soapOnly) count++;
    if (handDryerOnly) count++;
    if (recentlyVerifiedOnly) count++;
    if (minRating > 0.0) count++;
    return count;
  }

  /// Returns true if [restroom] matches all active filter categories.
  bool matches(Restroom restroom, {DateTime? now}) {
    if (!isActive) return true;

    // 1. Access Types (OR within category)
    if (accessTypes.isNotEmpty && !accessTypes.contains(restroom.accessType)) {
      return false;
    }

    // 2. Gender / Restroom Types (OR within category)
    if (genderTypes.isNotEmpty) {
      final matchesGender = genderTypes.any((g) {
        switch (g) {
          case GenderTypeFilter.male:
            return restroom.male;
          case GenderTypeFilter.female:
            return restroom.female;
          case GenderTypeFilter.allGender:
            return restroom.allGender;
        }
      });
      if (!matchesGender) return false;
    }

    // 3. Boolean Amenities (AND across categories)
    if (pwdAccessibleOnly && !restroom.pwdAccessible) return false;
    if (babyChangingOnly && !restroom.babyChanging) return false;
    if (bidetOnly && !restroom.hasBidet) return false;
    if (toiletPaperOnly && !restroom.hasToiletPaper) return false;
    if (soapOnly && !restroom.hasSoap) return false;
    if (handDryerOnly && !restroom.hasHandDryer) return false;

    // 4. Minimum Rating
    if (minRating > 0.0 && restroom.averageRating < minRating) {
      return false;
    }

    // 5. Recently Verified
    if (recentlyVerifiedOnly) {
      if (restroom.lastVerifiedAt == null) {
        return false;
      }
      final reference = now ?? DateTime.now();
      final diff = reference.difference(restroom.lastVerifiedAt!);
      if (diff < Duration.zero || diff > recentVerificationThreshold) {
        return false;
      }
    }

    return true;
  }

  DiscoveryFilters copyWith({
    Set<AccessType>? accessTypes,
    Set<GenderTypeFilter>? genderTypes,
    bool? pwdAccessibleOnly,
    bool? babyChangingOnly,
    bool? bidetOnly,
    bool? toiletPaperOnly,
    bool? soapOnly,
    bool? handDryerOnly,
    bool? recentlyVerifiedOnly,
    double? minRating,
  }) {
    return DiscoveryFilters(
      accessTypes: accessTypes ?? this.accessTypes,
      genderTypes: genderTypes ?? this.genderTypes,
      pwdAccessibleOnly: pwdAccessibleOnly ?? this.pwdAccessibleOnly,
      babyChangingOnly: babyChangingOnly ?? this.babyChangingOnly,
      bidetOnly: bidetOnly ?? this.bidetOnly,
      toiletPaperOnly: toiletPaperOnly ?? this.toiletPaperOnly,
      soapOnly: soapOnly ?? this.soapOnly,
      handDryerOnly: handDryerOnly ?? this.handDryerOnly,
      recentlyVerifiedOnly: recentlyVerifiedOnly ?? this.recentlyVerifiedOnly,
      minRating: minRating ?? this.minRating,
    );
  }

  @override
  List<Object?> get props => [
    accessTypes,
    genderTypes,
    pwdAccessibleOnly,
    babyChangingOnly,
    bidetOnly,
    toiletPaperOnly,
    soapOnly,
    handDryerOnly,
    recentlyVerifiedOnly,
    minRating,
  ];
}

/// Filter options for restroom / gender designation.
enum GenderTypeFilter {
  male('Male'),
  female('Female'),
  allGender('All-Gender');

  final String label;
  const GenderTypeFilter(this.label);
}
