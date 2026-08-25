/// THE ONLY FILE IN `lib/` ALLOWED TO CONTAIN COLOUR LITERALS.
///
/// `tool/check_no_raw_colors.dart` fails the build if a `Color(0x...)` literal
/// or a `Colors.*` reference appears anywhere else under `lib/`. Everything
/// else reads colours from [AppTokens], which is installed as a
/// [ThemeExtension] so both themes resolve through the same call:
///
/// ```dart
/// final tokens = AppTokens.of(context);
/// Container(color: tokens.colors.surfaceElevated);
/// ```
///
/// Palette is the "Slate & Marigold" design system from the Production Bible.
library;

import 'package:flutter/material.dart';

/// Per-theme colour set. Spacing/radii/motion do not change between themes,
/// so they live as static constants on [AppTokens] instead.
@immutable
final class AppColors {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHigh,
    required this.outline,
    required this.outlineSoft,
    required this.primary,
    required this.primaryDim,
    required this.onPrimary,
    required this.success,
    required this.warn,
    required this.info,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.onSurfaceFaint,
    required this.shadow,
    required this.foundWord,
  });

  /// Page ground, behind [surface].
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceHigh;

  final Color outline;
  final Color outlineSoft;

  /// Marigold. The single accent — used for the active selection, primary
  /// actions and progress.
  final Color primary;

  /// Muted marigold, for de-emphasised accents (dividers, inactive rails).
  final Color primaryDim;

  /// Foreground that sits on top of [primary].
  final Color onPrimary;

  final Color success;
  final Color warn;
  final Color info;

  final Color onSurface;
  final Color onSurfaceMuted;
  final Color onSurfaceFaint;

  final Color shadow;

  /// Six highlight colours for found words, in assignment order.
  ///
  /// Not picked by eye: these were selected by a search that maximised the
  /// minimum pairwise CIE ΔE simultaneously under normal, protanopic and
  /// deuteranopic vision, subject to a ≥3.5:1 contrast floor against the
  /// surface and ≥40° of hue separation. `found_word_palette_test.dart`
  /// re-runs the simulation and fails if any pair drifts too close, so a
  /// substitution here is checked rather than assumed.
  ///
  /// Reordering is safe (pairwise distance is a set property); substituting
  /// a colour is not.
  ///
  /// Colour alone is never the only cue — pair each entry with the matching
  /// [AppTokens.foundWordBorderWidths] value (Ch03 accessibility).
  final List<Color> foundWord;

  AppColors lerpTo(AppColors other, double t) {
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      outlineSoft: Color.lerp(outlineSoft, other.outlineSoft, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDim: Color.lerp(primaryDim, other.primaryDim, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      info: Color.lerp(info, other.info, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      onSurfaceFaint: Color.lerp(onSurfaceFaint, other.onSurfaceFaint, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      foundWord: [
        for (var i = 0; i < foundWord.length; i++)
          Color.lerp(foundWord[i], other.foundWord[i], t)!,
      ],
    );
  }
}

/// One elevation step: a tinted surface colour *plus* shadows.
///
/// Shadow alone reads as flat on the dark theme, where a drop shadow against
/// a near-black ground is nearly invisible — the surface tint is what actually
/// separates the layers there.
@immutable
final class AppElevationStyle {
  const AppElevationStyle({required this.surface, required this.shadows});

  /// The surface colour at this elevation, already composited.
  final Color surface;
  final List<BoxShadow> shadows;
}

/// Design tokens, resolved per theme. Read via [AppTokens.of].
@immutable
final class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({required this.colors, required this.brightness});

  final AppColors colors;
  final Brightness brightness;

  /// Reads the tokens installed on the ambient [Theme]. Throws rather than
  /// returning null: a missing extension means the app was built without
  /// [AppTheme], which is a wiring bug, not a runtime state.
  static AppTokens of(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>();
    if (tokens == null) {
      throw FlutterError(
        'AppTokens not found on the ambient Theme. Build the app with '
        'AppTheme.dark()/AppTheme.light() so the extension is installed.',
      );
    }
    return tokens;
  }

  // ---------------------------------------------------------------------
  // Spacing — 4 / 8 / 12 / 16 / 24 / 32 / 48
  // ---------------------------------------------------------------------

  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space48 = 48;

  /// The scale in order, for the Style Gallery and for any layout that steps
  /// through it programmatically.
  static const List<double> spacingScale = [
    space4,
    space8,
    space12,
    space16,
    space24,
    space32,
    space48,
  ];

  // ---------------------------------------------------------------------
  // Radii — 4 / 8 / 16
  // ---------------------------------------------------------------------

  static const double radius4 = 4;
  static const double radius8 = 8;
  static const double radius16 = 16;

  static const List<double> radiusScale = [radius4, radius8, radius16];

  static const BorderRadius borderRadius4 = BorderRadius.all(
    Radius.circular(radius4),
  );
  static const BorderRadius borderRadius8 = BorderRadius.all(
    Radius.circular(radius8),
  );
  static const BorderRadius borderRadius16 = BorderRadius.all(
    Radius.circular(radius16),
  );

  // ---------------------------------------------------------------------
  // Accessibility: found-word cues
  // ---------------------------------------------------------------------

  /// Border weight per found-word colour index, so two highlights differ by
  /// stroke as well as hue. Roughly 8% of men have a colour vision deficiency
  /// (Ch03) — hue alone is not an accessible cue.
  static const List<double> foundWordBorderWidths = [
    1.5,
    3.0,
    1.5,
    3.0,
    2.25,
    2.25,
  ];

  /// Minimum interactive target, in dp (Ch03: grid cells included).
  static const double minTouchTarget = 44;

  // ---------------------------------------------------------------------
  // Elevation — 3 levels, tint + shadow
  // ---------------------------------------------------------------------

  AppElevationStyle get elevation1 => _elevation(
    tintOpacity: brightness == Brightness.dark ? 0.04 : 0.03,
    blur: 4,
    dy: 1,
    shadowOpacity: brightness == Brightness.dark ? 0.34 : 0.10,
  );

  AppElevationStyle get elevation2 => _elevation(
    tintOpacity: brightness == Brightness.dark ? 0.07 : 0.05,
    blur: 10,
    dy: 3,
    shadowOpacity: brightness == Brightness.dark ? 0.40 : 0.13,
  );

  AppElevationStyle get elevation3 => _elevation(
    tintOpacity: brightness == Brightness.dark ? 0.11 : 0.08,
    blur: 22,
    dy: 8,
    shadowOpacity: brightness == Brightness.dark ? 0.46 : 0.16,
  );

  /// The three levels in order, for the Style Gallery.
  List<AppElevationStyle> get elevations => [
    elevation1,
    elevation2,
    elevation3,
  ];

  AppElevationStyle _elevation({
    required double tintOpacity,
    required double blur,
    required double dy,
    required double shadowOpacity,
  }) {
    return AppElevationStyle(
      surface: Color.alphaBlend(
        colors.primary.withValues(alpha: tintOpacity),
        colors.surfaceElevated,
      ),
      shadows: [
        BoxShadow(
          color: colors.shadow.withValues(alpha: shadowOpacity),
          blurRadius: blur,
          offset: Offset(0, dy),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Palettes
  // ---------------------------------------------------------------------

  /// Dark is the product default — a relaxed puzzle played in the evening,
  /// and the palette the Production Bible specifies.
  static const AppColors darkColors = AppColors(
    background: Color(0xFF080F0D),
    surface: Color(0xFF0D1917),
    surfaceElevated: Color(0xFF122320),
    surfaceHigh: Color(0xFF18302B),
    outline: Color(0xFF1E3A33),
    outlineSoft: Color(0xFF162924),
    primary: Color(0xFFE8A33D),
    primaryDim: Color(0xFF8A6021),
    onPrimary: Color(0xFF080F0D),
    success: Color(0xFF5FD4A8),
    warn: Color(0xFFE4685A),
    info: Color(0xFF6FA8DC),
    onSurface: Color(0xFFEDE7D9),
    onSurfaceMuted: Color(0xFFA9B8B0),
    onSurfaceFaint: Color(0xFF6E827A),
    shadow: Color(0xFF000000),
    foundWord: [
      Color(0xFF59A8CF), // sky blue
      Color(0xFFD2482D), // vermillion
      Color(0xFF9FDBC7), // mint
      Color(0xFFD2D22D), // chartreuse
      Color(0xFF7070E1), // periwinkle
      Color(0xFFAEE892), // spring green
    ],
  );

  /// Light theme, kept warm rather than clinical white — the same product,
  /// legible outdoors and for players who simply prefer it. Also serves the
  /// high-contrast option promised in Ch03.
  static const AppColors lightColors = AppColors(
    background: Color(0xFFFBF7EF),
    surface: Color(0xFFFFFDF8),
    surfaceElevated: Color(0xFFF5EFE3),
    surfaceHigh: Color(0xFFEDE5D6),
    outline: Color(0xFFD3C6AF),
    outlineSoft: Color(0xFFE6DCCA),
    primary: Color(0xFF9A6008),
    primaryDim: Color(0xFFC79433),
    onPrimary: Color(0xFFFFFDF8),
    success: Color(0xFF0F6B4A),
    warn: Color(0xFFB03A2E),
    info: Color(0xFF1F5B92),
    onSurface: Color(0xFF14201D),
    onSurfaceMuted: Color(0xFF44554F),
    onSurfaceFaint: Color(0xFF6E827A),
    shadow: Color(0xFF2A2118),
    foundWord: [
      Color(0xFF298FC2), // blue
      Color(0xFF761919), // deep red
      Color(0xFF389475), // teal
      Color(0xFFA87C24), // ochre
      Color(0xFF68275D), // plum
      Color(0xFF2929C2), // indigo
    ],
  );

  static const AppTokens dark = AppTokens(
    colors: darkColors,
    brightness: Brightness.dark,
  );

  static const AppTokens light = AppTokens(
    colors: lightColors,
    brightness: Brightness.light,
  );

  @override
  AppTokens copyWith({AppColors? colors, Brightness? brightness}) {
    return AppTokens(
      colors: colors ?? this.colors,
      brightness: brightness ?? this.brightness,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      colors: colors.lerpTo(other.colors, t),
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }
}
