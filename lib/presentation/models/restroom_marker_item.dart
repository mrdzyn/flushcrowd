import 'package:equatable/equatable.dart';

import '../../domain/models/coordinates.dart';
import '../../domain/models/restroom.dart';

/// Presentation-layer representation of a restroom map marker.
///
/// Decouples business logic from platform-specific Google Maps Marker objects,
/// ensuring stable identity by restroom ID and testable selection state.
class RestroomMarkerItem extends Equatable {
  final String id;
  final Coordinates coordinates;
  final String name;
  final String? floor;
  final double? averageRating;
  final bool isSelected;

  const RestroomMarkerItem({
    required this.id,
    required this.coordinates,
    required this.name,
    this.floor,
    this.averageRating,
    this.isSelected = false,
  });

  /// Factory creating a marker from domain [Restroom].
  factory RestroomMarkerItem.fromRestroom(
    Restroom restroom, {
    bool isSelected = false,
  }) {
    return RestroomMarkerItem(
      id: restroom.id,
      coordinates: restroom.coordinates,
      name: restroom.name,
      floor: restroom.floor,
      averageRating: restroom.averageRating,
      isSelected: isSelected,
    );
  }

  RestroomMarkerItem copyWith({bool? isSelected}) {
    return RestroomMarkerItem(
      id: id,
      coordinates: coordinates,
      name: name,
      floor: floor,
      averageRating: averageRating,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  List<Object?> get props => [
    id,
    coordinates,
    name,
    floor,
    averageRating,
    isSelected,
  ];

  @override
  String toString() =>
      'RestroomMarkerItem(id: $id, name: $name, selected: $isSelected, coords: $coordinates)';
}
