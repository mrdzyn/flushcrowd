import 'package:flutter/material.dart';

/// Corner radius design tokens for cards, buttons, dialogs, and sheets.
class AppRadii {
  AppRadii._();

  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double pill = 28.0;
  static const double circle = 999.0;

  // BorderRadius helpers
  static const BorderRadius smBorder = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdBorder = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgBorder = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlBorder = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillBorder = BorderRadius.all(
    Radius.circular(pill),
  );
  static const BorderRadius topSheetBorder = BorderRadius.vertical(
    top: Radius.circular(xxl),
  );
}
