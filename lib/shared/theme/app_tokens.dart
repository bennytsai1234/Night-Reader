import 'package:flutter/material.dart';

/// Primitive color palette — 夜讀 (Yè Dú) Design Tokens
class AppPalette {
  AppPalette._();

  // Pigments
  static const Color cinnabar = Color(0xFF7E2E2A); // primary light
  static const Color cinnabarDark = Color(0xFFD67B6E); // primary dark
  static const Color tea = Color(0xFF8A6F3A); // warning light
  static const Color teaDark = Color(0xFFC7A867); // warning dark
  static const Color azurite = Color(0xFF4B6E8C); // info light
  static const Color azuriteDark = Color(0xFF8FB0C9); // info dark
  static const Color rust = Color(0xFFB0463A); // danger light
  static const Color rustDark = Color(0xFFD98B7E); // danger dark
  static const Color moss = Color(0xFF5F7355); // success light
  static const Color mossDark = Color(0xFF9DB38F); // success dark
  static const Color gold = Color(0xFFB6914A); // highlight
  static const Color aubergine = Color(0xFF6B5570); // cover pigment

  // Paper (Light mode surfaces)
  static const Color paper50  = Color(0xFFFFFBF2);
  static const Color paper100 = Color(0xFFFAF5E9);
  static const Color paper200 = Color(0xFFF4EFE3);
  static const Color paper300 = Color(0xFFECE5D4);
  static const Color paper400 = Color(0xFFDCD2BD);

  // Ink (Dark mode surfaces & text)
  static const Color ink50  = Color(0xFFF4EDD7);
  static const Color ink100 = Color(0xFFC8C0AC);
  static const Color ink200 = Color(0xFF8A8473);
  static const Color ink300 = Color(0xFF5F5A4D);
  static const Color ink400 = Color(0xFF3D392F);
  static const Color ink500 = Color(0xFF2A271E);
  static const Color ink600 = Color(0xFF1A1612);
  static const Color ink700 = Color(0xFF100D0A);
  static const Color ink900 = Color(0xFF060403);
}

/// Spacing scale (logical pixels).
class AppSpacing {
  AppSpacing._();
  static const double xs   = 4.0;
  static const double sm   = 6.0;
  static const double md   = 10.0;
  static const double lg   = 14.0;
  static const double xl   = 20.0;
  static const double xxl  = 28.0;
  static const double xxxl = 40.0;
}

/// Border-radius tokens.
class AppRadius {
  AppRadius._();
  static const double xs   = 4.0;
  static const double sm   = 6.0;
  static const double md   = 10.0;
  static const double lg   = 14.0;
  static const double xl   = 20.0;
  static const double pill = 999.0;

  static const BorderRadius cardXs    = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius cardSm    = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius cardMd    = BorderRadius.all(Radius.circular(md));
  static const BorderRadius cardLg    = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius cardXl    = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillShape = BorderRadius.all(Radius.circular(pill));
  static const BorderRadius topSheetLg =
      BorderRadius.vertical(top: Radius.circular(lg));
  static const BorderRadius topSheetXl =
      BorderRadius.vertical(top: Radius.circular(xl));
}
