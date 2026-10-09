import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/commands/create_restroom_command.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/duplicate_scan_result.dart';
import '../../domain/repositories/restroom_repository.dart';
import '../../domain/services/duplicate_detection_service.dart';
import '../components/bottom_sheets/duplicate_warning_sheet.dart';
import '../components/feedback/empty_state_view.dart';
import '../components/navigation/loo_bottom_nav_bar.dart';
import '../state/map_discovery_notifier.dart';
import '../state/restroom_id_generator.dart';
import 'add_restroom_form_screen.dart';
import 'add_restroom_location_screen.dart';
import 'explore_restrooms_screen.dart';
import 'map_discovery_screen.dart';

/// Main application shell housing the bottom navigation bar and active tab screens.
class MainShellScreen extends StatefulWidget {
  final MapWidgetBuilder? addLocationMapBuilder;
  final MapWidgetBuilder? discoveryMapBuilder;
  final RestroomIdGenerator? formIdGenerator;
  final DuplicateDetectionService? duplicateDetectionService;

  const MainShellScreen({
    super.key,
    this.addLocationMapBuilder,
    this.discoveryMapBuilder,
    this.formIdGenerator,
    this.duplicateDetectionService,
  });

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentTabIndex = 0;
  bool _isOpeningAddLocation = false;
  Coordinates? _discoveryCameraTarget;
  CreateRestroomCommand? _preservedDraftCommand;
  Coordinates? _preservedDraftCoordinates;

  void _handleDiscoveryCameraTargetChanged(Coordinates target) {
    _discoveryCameraTarget = target;
  }

  Future<void> _openAddRestroom() async {
    if (_isOpeningAddLocation) return;

    // Check if user has a preserved draft from a previous dismissed duplicate warning
    if (_preservedDraftCommand != null && _preservedDraftCoordinates != null) {
      final resume = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Resume Contribution?'),
          content: Text(
            'You have a saved draft for "${_preservedDraftCommand!.draft.name}". Would you like to resume editing this draft or discard it to start fresh?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Discard & Start New'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Resume Draft'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (resume == true) {
        await _continueWithForm(
          confirmedCoordinates: _preservedDraftCoordinates!,
          initialCommand: _preservedDraftCommand,
        );
        return;
      } else if (resume == false) {
        // Explicit abandonment of preserved draft
        _preservedDraftCommand = null;
        _preservedDraftCoordinates = null;
      } else {
        // User dismissed resume prompt dialog; keep draft preserved
        return;
      }
    }

    _isOpeningAddLocation = true;
    try {
      final Coordinates? confirmedCoordinates = await Navigator.of(context)
          .push<Coordinates>(
            AddRestroomLocationScreen.route(
              initialCoordinates: _discoveryCameraTarget,
              mapBuilder: widget.addLocationMapBuilder,
            ),
          );

      if (!mounted) return;

      if (confirmedCoordinates != null) {
        await _continueWithForm(confirmedCoordinates: confirmedCoordinates);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningAddLocation = false;
        });
      }
    }
  }

  Future<void> _continueWithForm({
    required Coordinates confirmedCoordinates,
    CreateRestroomCommand? initialCommand,
  }) async {
    final CreateRestroomCommand? command = await Navigator.of(context)
        .push<CreateRestroomCommand>(
          AddRestroomFormScreen.route(
            coordinates: confirmedCoordinates,
            idGenerator: widget.formIdGenerator,
            initialCommand: initialCommand,
          ),
        );

    if (!mounted) return;

    if (command != null) {
      await _processDraftSubmissionFlow(
        command: command,
        confirmedCoordinates: confirmedCoordinates,
      );
    }
  }

  Future<void> _processDraftSubmissionFlow({
    required CreateRestroomCommand command,
    required Coordinates confirmedCoordinates,
  }) async {
    final duplicateService =
        widget.duplicateDetectionService ?? const DuplicateDetectionService();

    DuplicateScanResult scanResult = const DuplicateScanResult(candidates: []);
    try {
      final repo = context.read<RestroomRepository>();
      scanResult = await duplicateService.findDuplicatesNearby(
        draft: command.draft,
        repository: repo,
      );
    } catch (e) {
      // Advisory scan: fail open so user is never blocked
      scanResult = DuplicateScanResult.failedOpen(errorMessage: e.toString());
    }

    if (!mounted) return;

    if (scanResult.hasDuplicates) {
      await _handleDuplicateWarning(
        command: command,
        confirmedCoordinates: confirmedCoordinates,
        scanResult: scanResult,
      );
    } else {
      // Clear preserved draft since user passed validation without duplicates
      _preservedDraftCommand = null;
      _preservedDraftCoordinates = null;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final String feedbackMessage;
      if (scanResult.hasQueryError) {
        feedbackMessage = 'Duplicate check could not be completed, but contribution proceeds (advisory fail-open). Restroom submission comes in Milestone P2.5.';
      } else if (!scanResult.isComplete) {
        feedbackMessage = 'No likely duplicates found in the results checked, but the duplicate scan was incomplete. Restroom submission comes in Milestone P2.5.';
      } else {
        feedbackMessage = 'No likely duplicates found nearby. Restroom submission comes in Milestone P2.5.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(feedbackMessage),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleDuplicateWarning({
    required CreateRestroomCommand command,
    required Coordinates confirmedCoordinates,
    required DuplicateScanResult scanResult,
  }) async {
    final action = await DuplicateWarningSheet.show(
      context,
      candidates: scanResult.candidates,
    );

    if (!mounted) return;

    if (action is ViewExistingRestroomAction) {
      // Explicit abandonment of draft
      _preservedDraftCommand = null;
      _preservedDraftCoordinates = null;

      setState(() => _currentTabIndex = 0);
      try {
        final discoveryNotifier = context.read<MapDiscoveryNotifier>();
        discoveryNotifier.focusOnRestroom(
          action.restroom,
          zoom: AppConstants.defaultZoomLevel,
          openPreview: true,
        );
      } catch (_) {}
      return;
    } else if (action is ProceedWithSubmissionAction) {
      // Acknowledged warning; proceeding to submission (P2.5)
      _preservedDraftCommand = null;
      _preservedDraftCoordinates = null;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Duplicate warning acknowledged. Restroom submission comes in Milestone P2.5.',
          ),
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } else {
      // action == null: User dismissed warning sheet.
      // Explicitly preserve stable command, coordinates, and restroomId.
      _preservedDraftCommand = command;
      _preservedDraftCoordinates = confirmedCoordinates;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Draft for "${command.draft.name}" preserved. Tap Review to re-check duplicates or resume.',
          ),
          action: SnackBarAction(
            label: 'Review',
            onPressed: () {
              if (mounted) {
                _handleDuplicateWarning(
                  command: command,
                  confirmedCoordinates: confirmedCoordinates,
                  scanResult: scanResult,
                );
              }
            },
          ),
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          MapDiscoveryScreen(
            mapBuilder: widget.discoveryMapBuilder,
            onCameraTargetChanged: _handleDiscoveryCameraTargetChanged,
          ),
          ExploreRestroomsScreen(
            onSelectRestroom: (restroom) {
              setState(() => _currentTabIndex = 0);
            },
            onSwitchToMap: () {
              setState(() => _currentTabIndex = 0);
            },
          ),
          const SizedBox.shrink(),
          const _PhasePlaceholderScreen(
            icon: Icons.favorite_rounded,
            title: 'Saved Places',
            phaseDescription: 'Future phases will allow saving bookmarked restroom facilities.',
          ),
          const _PhasePlaceholderScreen(
            icon: Icons.settings_rounded,
            title: 'More & Support',
            phaseDescription:
                '${AppConstants.appName} v1.0.0 (Phase 0 Foundation)\nCommunity-powered, privacy-first.',
          ),
        ],
      ),
      bottomNavigationBar: LooBottomNavBar(
        currentIndex: _currentTabIndex,
        onTabSelected: (index) {
          if (index == 2) {
            _openAddRestroom();
          } else {
            setState(() => _currentTabIndex = index);
          }
        },
      ),
    );
  }
}

class _PhasePlaceholderScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String phaseDescription;

  const _PhasePlaceholderScreen({
    required this.icon,
    required this.title,
    required this.phaseDescription,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyStateView(
            icon: icon,
            title: title,
            description: phaseDescription,
          ),
        ),
      ),
    );
  }
}
