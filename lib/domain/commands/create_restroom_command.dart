import 'package:equatable/equatable.dart';

import '../models/restroom_draft.dart';

/// Command representing an explicit, idempotent request to create a restroom.
///
/// Holds the stable [restroomId] allocated once by application state and retained
/// across retries, timeouts, and ambiguous commit reconciliations.
class CreateRestroomCommand extends Equatable {
  final String restroomId;
  final RestroomDraft draft;

  const CreateRestroomCommand({required this.restroomId, required this.draft});

  @override
  List<Object?> get props => [restroomId, draft];
}
