import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/commands/create_restroom_command.dart';
import '../../domain/models/coordinates.dart';
import '../../domain/models/duplicate_candidate.dart';
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

  void _handleDiscoveryCameraTargetChanged(Coordinates target) {
    _discoveryCameraTarget = target;
  }

  Future<void> _openAddRestroom() async {
    if (_isOpeningAddLocation) return;
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
        final CreateRestroomCommand? command = await Navigator.of(context)
            .push<CreateRestroomCommand>(
              AddRestroomFormScreen.route(
                coordinates: confirmedCoordinates,
                idGenerator: widget.formIdGenerator,
              ),
            );

        if (!mounted) return;

        if (command != null) {
          final duplicateService =
              widget.duplicateDetectionService ??
              const DuplicateDetectionService();

          List<DuplicateCandidate> duplicateCandidates = const [];
          try {
            final repo = context.read<RestroomRepository>();
            duplicateCandidates = await duplicateService.findDuplicatesNearby(
              draft: command.draft,
              repository: repo,
            );
          } catch (_) {
            // Advisory scan: fail open so user is never blocked
            duplicateCandidates = const [];
          }

          if (!mounted) return;

          if (duplicateCandidates.isNotEmpty) {
            final action = await DuplicateWarningSheet.show(
              context,
              candidates: duplicateCandidates,
            );

            if (!mounted) return;

            if (action is ViewExistingRestroomAction) {
              try {
                final discoveryNotifier = context.read<MapDiscoveryNotifier>();
                discoveryNotifier.selectRestroom(action.restroom);
              } catch (_) {}
              setState(() => _currentTabIndex = 0);
              return;
            } else if (action is ProceedWithSubmissionAction) {
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
            }
          } else {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Restroom details validated. Restroom submission comes in Milestone P2.5.',
                ),
                duration: Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningAddLocation = false;
        });
      }
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
