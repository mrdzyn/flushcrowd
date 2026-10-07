import 'package:flutter/material.dart';

/// Semantic color palette for FlushCrowd design system,
/// reflecting the canonical mobile UX reference.
class AppColors {
  AppColors._();

  // Primary brand colors
  static const Color primary = Color(0xFF1E6FFB);
  static const Color primaryDark = Color(0xFF0F52BA);
  static const Color primaryLight = Color(0xFFE8F1FE);

  // Background and surfaces
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F5F9);

  // Neutral borders and dividers
  static const Color border = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFCBD5E1);

  // Text colors
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textTertiary = Color(0xFF94A3B8);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Status colors
  static const Color success = Color(0xFF10B981);
  static const Color successContainer = Color(0xFFECFDF5);
  static const Color onSuccessContainer = Color(0xFF065F46);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningContainer = Color(0xFFFEF3C7);
  static const Color onWarningContainer = Color(0xFF92400E);

  static const Color error = Color(0xFFEF4444);
  static const Color errorContainer = Color(0xFFFEE2E2);
  static const Color onErrorContainer = Color(0xFF991B1B);

  // Map accents
  static const Color mapPinRestroom = Color(0xFF1E6FFB);
  static const Color mapUserPulse = Color(0x331E6FFB);
  static const Color ratingStar = Color(0xFFF59E0B);
}
