import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../components/feedback/empty_state_view.dart';
import '../components/navigation/loo_bottom_nav_bar.dart';
import 'map_discovery_screen.dart';

/// Main application shell housing the bottom navigation bar and active tab screens.
class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentTabIndex,
        children: const [
          MapDiscoveryScreen(),
          _PhasePlaceholderScreen(
            icon: Icons.explore_rounded,
            title: 'Explore Restrooms',
            phaseDescription: 'Phase 1 will deliver the nearby list and categorized explore view.',
          ),
          _PhasePlaceholderScreen(
            icon: Icons.add_location_alt_rounded,
            title: 'Add a Restroom',
            phaseDescription:
                'Phase 2 will introduce the community contribution workflow.',
          ),
          _PhasePlaceholderScreen(
            icon: Icons.favorite_rounded,
            title: 'Saved Places',
            phaseDescription: 'Future phases will allow saving bookmarked restroom facilities.',
          ),
          _PhasePlaceholderScreen(
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
          setState(() => _currentTabIndex = index);
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
