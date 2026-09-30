import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../components/buttons/loo_primary_button.dart';
import '../state/auth_notifier.dart';
import '../state/location_notifier.dart';
import 'main_shell_screen.dart';

/// Splash and Value Proposition screen matching canonical UX mockup Item 1.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isNavigating = false;

  Future<void> _handleGetStarted() async {
    setState(() => _isNavigating = true);

    final authNotifier = context.read<AuthNotifier>();
    final locationNotifier = context.read<LocationNotifier>();

    // 1. Establish anonymous session
    if (!authNotifier.isAuthenticated) {
      await authNotifier.signInAnonymously();
    }

    // 2. Request foreground location permission
    await locationNotifier.requestLocationPermission();

    if (!mounted) return;

    // 3. Navigate to Main Discovery Shell
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const MainShellScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal * 1.5,
            vertical: AppSpacing.screenVertical,
          ),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Brand Pin Logo
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.mapUserPulse,
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.wc_rounded,
                    color: AppColors.surface,
                    size: 52,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Title and Tagline
              const Text(
                AppConstants.appName,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                AppConstants.appTagline,
                style: AppTypography.bodyMedium,
                textAlign: TextAlign.center,
              ),

              const Spacer(flex: 2),

              // Value Proposition Checklist
              Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: AppRadii.xlBorder,
                  border: Border.all(color: AppColors.border, width: 1),
                ),
                child: const Column(
                  children: [
                    _FeatureRow(
                      icon: Icons.near_me_outlined,
                      text: 'Find nearby restrooms',
                    ),
                    SizedBox(height: AppSpacing.md),
                    _FeatureRow(
                      icon: Icons.star_border_rounded,
                      text: 'See ratings and amenities',
                    ),
                    SizedBox(height: AppSpacing.md),
                    _FeatureRow(
                      icon: Icons.add_circle_outline_rounded,
                      text: 'Add and help others',
                    ),
                    SizedBox(height: AppSpacing.md),
                    _FeatureRow(
                      icon: Icons.lock_outline_rounded,
                      text: 'No account required',
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 3),

              // Primary Action
              LooPrimaryButton(
                label: 'Get Started',
                isLoading: _isNavigating,
                onPressed: _handleGetStarted,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodyLarge.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
