import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/commands/create_restroom_command.dart';
import '../../domain/models/coordinates.dart';
import '../components/feedback/empty_state_view.dart';
import '../components/navigation/loo_bottom_nav_bar.dart';
import '../state/restroom_id_generator.dart';
import 'add_restroom_form_screen.dart';
import 'add_restroom_location_screen.dart';
import 'map_discovery_screen.dart';

/// Main application shell housing the bottom navigation bar and active tab screens.
class MainShellScreen extends StatefulWidget {
  final MapWidgetBuilder? addLocationMapBuilder;
  final MapWidgetBuilder? discoveryMapBuilder;
  final RestroomIdGenerator? formIdGenerator;

  const MainShellScreen({
    super.key,
    this.addLocationMapBuilder,
    this.discoveryMapBuilder,
    this.formIdGenerator,
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
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Restroom details validated. Duplicate check comes in the next milestone.',
              ),
              duration: Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
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
          const _PhasePlaceholderScreen(
            icon: Icons.explore_rounded,
            title: 'Explore Restrooms',
            phaseDescription: 'Phase 1 will deliver the nearby list and categorized explore view.',
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
