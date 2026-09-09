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

import '../../domain/theme/app_theme_variant.dart';

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
    required this.foundWordFlash,
    required this.regionAccent,
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

  /// The 0ms colour of the correct-word reveal (`found_word_reveal.dart`),
  /// which eases into the word's assigned [foundWord] hue over 90ms. Ch03
  /// specifies this literally as "white" rather than a themed tone — a
  /// punchy flash reading the same on both themes — so this is the one
  /// [AppColors] field that is deliberately identical between [darkColors]
  /// and [lightColors] rather than independently tuned.
  final Color foundWordFlash;

  /// Journey-map region accents (Ch02/P11), indexed by
  /// `JourneyRegion.accentIndex`.
  ///
  /// Six, cycling — `JourneyRegion.accentCount` says why: thirty visually
  /// distinct accents do not exist, and a player sees two or three regions at
  /// once on a scrolling map, so a cycle reads as variety.
  ///
  /// A SEPARATE LIST FROM [foundWord], despite both being six colours that
  /// sit on the same surface. Reusing that palette would couple a decorative
  /// map accent to a set whose members were chosen by maximising pairwise
  /// CIE ΔE under three kinds of colour vision, and whose ordering
  /// `found_word_palette_test.dart` actively guards. A region accent has no
  /// such job — nothing about the map asks a player to tell two regions
  /// apart by hue — so tying the two together would mean every future map
  /// restyle had to re-run an accessibility search it does not need.
  final List<Color> regionAccent;

  /// The three built-in board backgrounds, indexed by
  /// `BackgroundStyle.gradientIndex`.
  ///
  /// DERIVED, not declared: each one is the page colour blended a little way
  /// toward a hue this palette already defines, so there is not one new colour
  /// literal here and the light theme gets its own correct version of "ember"
  /// for free. It also means a future palette retune moves the backgrounds
  /// with it instead of leaving three hand-picked stops behind.
  ///
  /// A getter rather than a field because [Color.lerp] is not `const` and this
  /// class is. Cheap enough: it is read when the chosen style changes, not per
  /// frame — `AppBackground` paints inside a `RepaintBoundary` and rebuilds
  /// only on that setting.
  List<AppBackgroundGradient> get backgroundGradients => [
    AppBackgroundGradient(from: background, to: surfaceHigh),
    AppBackgroundGradient(
      from: background,
      to: Color.lerp(background, primaryDim, _gradientBlend)!,
    ),
    AppBackgroundGradient(
      from: background,
      to: Color.lerp(background, regionAccent.first, _gradientBlend)!,
    ),
  ];

  /// How far a gradient travels from the page colour toward its accent. Low on
  /// purpose: this sits behind a letter grid all session, and a background a
  /// player notices twice is one they are still noticing on level 200.
  static const double _gradientBlend = 0.5;

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
      foundWordFlash: Color.lerp(foundWordFlash, other.foundWordFlash, t)!,
      regionAccent: [
        for (var i = 0; i < regionAccent.length; i++)
          Color.lerp(regionAccent[i], other.regionAccent[i], t)!,
      ],
    );
  }
}

/// One board background: two stops, painted top to bottom.
///
/// A named pair rather than a `List<Color>` so a call site reads `from`/`to`
/// instead of `[0]`/`[1]`, and so the direction is stated once here rather
/// than assumed at every use.
@immutable
final class AppBackgroundGradient {
  const AppBackgroundGradient({required this.from, required this.to});

  final Color from;
  final Color to;

  @override
  bool operator ==(Object other) =>
      other is AppBackgroundGradient && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
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
  // ---- shared between every palette in a family --------------------------
  //
  // Extracted from [darkColors]/[lightColors] rather than retyped per theme,
  // and the sharing is a decision rather than a saving. The found-word six
  // were not picked by eye: they came out of a search maximising the minimum
  // pairwise CIE deltaE under normal, protanopic and deuteranopic vision, and
  // `found_word_palette_test.dart` re-runs that search on every build. Giving
  // each of the eight themes its own six would mean eight such searches to
  // keep passing forever, for a set of colours a player never chooses. So a
  // theme moves its GROUND, its TEXT and its ACCENT; what a found word looks
  // like is a property of the family, checked once per family surface.

  static const Color _darkSuccess = Color(0xFF5FD4A8);
  static const Color _darkWarn = Color(0xFFE4685A);
  static const Color _darkInfo = Color(0xFF6FA8DC);
  static const Color _darkShadow = Color(0xFF000000);

  static const Color _lightSuccess = Color(0xFF0F6B4A);
  static const Color _lightWarn = Color(0xFFB03A2E);
  static const Color _lightInfo = Color(0xFF1F5B92);
  static const Color _lightShadow = Color(0xFF2A2118);

  /// Ch03 names this literally as "white" on both families — see
  /// [AppColors.foundWordFlash].
  static const Color _foundWordFlash = Color(0xFFFFFFFF);

  static const List<Color> _darkFoundWord = [
    Color(0xFF59A8CF), // sky blue
    Color(0xFFD2482D), // vermillion
    Color(0xFF9FDBC7), // mint
    Color(0xFFD2D22D), // chartreuse
    Color(0xFF7070E1), // periwinkle
    Color(0xFFAEE892), // spring green
  ];

  static const List<Color> _lightFoundWord = [
    Color(0xFF298FC2), // blue
    Color(0xFF761919), // deep red
    Color(0xFF389475), // teal
    Color(0xFFA87C24), // ochre
    Color(0xFF68275D), // plum
    Color(0xFF2929C2), // indigo
  ];

  static const List<Color> _darkRegionAccent = [
    Color(0xFF4FA3A5), // teal
    Color(0xFF8E7CC3), // violet
    Color(0xFFD98E4A), // amber
    Color(0xFF5B8DD9), // steel blue
    Color(0xFFC96A8A), // rose
    Color(0xFF7FB069), // moss
  ];

  static const List<Color> _lightRegionAccent = [
    Color(0xFF2A7F81), // teal
    Color(0xFF5F4B9B), // violet
    Color(0xFFA8611C), // amber
    Color(0xFF2F5FA8), // steel blue
    Color(0xFF9B3A5C), // rose
    Color(0xFF4A7A32), // moss
  ];

  /// Dark is the product default — a relaxed puzzle played in the evening,
  /// and the palette the Production Bible specifies. Also
  /// [AppThemeVariant.midnight], unchanged to the byte since P02: a player who
  /// pins that look gets exactly the app they already had.
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
    success: _darkSuccess,
    warn: _darkWarn,
    info: _darkInfo,
    onSurface: Color(0xFFEDE7D9),
    onSurfaceMuted: Color(0xFFA9B8B0),
    onSurfaceFaint: Color(0xFF6E827A),
    shadow: _darkShadow,
    foundWord: _darkFoundWord,
    foundWordFlash: _foundWordFlash,
    regionAccent: _darkRegionAccent,
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
    success: _lightSuccess,
    warn: _lightWarn,
    info: _lightInfo,
    onSurface: Color(0xFF14201D),
    onSurfaceMuted: Color(0xFF44554F),
    onSurfaceFaint: Color(0xFF6E827A),
    shadow: _lightShadow,
    foundWord: _lightFoundWord,
    foundWordFlash: _foundWordFlash,
    regionAccent: _lightRegionAccent,
  );

  // ---- the six added looks -----------------------------------------------
  //
  // MEASURED, NOT PICKED BY EYE. Every ground and text step below reuses the
  // LIGHTNESS of the corresponding step in its family above; only hue and
  // saturation move. That is the whole reason these are safe to add: contrast
  // is overwhelmingly a function of lightness, so a palette built this way
  // starts within a rounding error of a ratio the shipped app already proved
  // legible, and `found_word_palette_test.dart` then checks each one rather
  // than taking it on trust.
  //
  // Each accent additionally had to sit at least as far from its family's
  // found-word six as the shipped marigold already does (deltaE 13.7 on dark,
  // 8.6 on light, under all three vision models). That bar is not a number
  // invented here — it is the separation the live app has always had between
  // the selection capsule under the player's finger and the words already
  // found, and it is why some obvious accents (an orange on the forest ground,
  // a red on the sand one) were rejected: they collide with a found-word hue.

  /// Deep navy ground, aqua accent.
  static const AppColors deepSeaColors = AppColors(
    background: Color(0xFF070B10),
    surface: Color(0xFF0C131B),
    surfaceElevated: Color(0xFF101A25),
    surfaceHigh: Color(0xFF152333),
    outline: Color(0xFF1B2B3E),
    outlineSoft: Color(0xFF141F2C),
    primary: Color(0xFF6FD2E2),
    primaryDim: Color(0xFF3493A2),
    onPrimary: Color(0xFF070B10),
    success: _darkSuccess,
    warn: _darkWarn,
    info: _darkInfo,
    onSurface: Color(0xFFD9E3ED),
    onSurfaceMuted: Color(0xFFA9B0B8),
    onSurfaceFaint: Color(0xFF6E7882),
    shadow: _darkShadow,
    foundWord: _darkFoundWord,
    foundWordFlash: _foundWordFlash,
    regionAccent: _darkRegionAccent,
  );

  /// Aubergine ground, rose accent.
  static const AppColors twilightColors = AppColors(
    background: Color(0xFF0C080F),
    surface: Color(0xFF140D19),
    surfaceElevated: Color(0xFF1C1223),
    surfaceHigh: Color(0xFF261830),
    outline: Color(0xFF2E1E3A),
    outlineSoft: Color(0xFF211629),
    primary: Color(0xFFDA4B71),
    primaryDim: Color(0xFF812941),
    onPrimary: Color(0xFF0C080F),
    success: _darkSuccess,
    warn: _darkWarn,
    info: _darkInfo,
    onSurface: Color(0xFFE8D9ED),
    onSurfaceMuted: Color(0xFFB4A9B8),
    onSurfaceFaint: Color(0xFF7D6E82),
    shadow: _darkShadow,
    foundWord: _darkFoundWord,
    foundWordFlash: _foundWordFlash,
    regionAccent: _darkRegionAccent,
  );

  /// Pine ground, new-leaf accent.
  static const AppColors forestColors = AppColors(
    background: Color(0xFF071008),
    surface: Color(0xFF0B1B0D),
    surfaceElevated: Color(0xFF0F2612),
    surfaceHigh: Color(0xFF143419),
    outline: Color(0xFF1A3E1F),
    outlineSoft: Color(0xFF132C17),
    primary: Color(0xFFDAEB70),
    primaryDim: Color(0xFFA0B22F),
    onPrimary: Color(0xFF071008),
    success: _darkSuccess,
    warn: _darkWarn,
    info: _darkInfo,
    onSurface: Color(0xFFDCEDD9),
    onSurfaceMuted: Color(0xFFABB8A9),
    onSurfaceFaint: Color(0xFF71826E),
    shadow: _darkShadow,
    foundWord: _darkFoundWord,
    foundWordFlash: _foundWordFlash,
    regionAccent: _darkRegionAccent,
  );

  /// Neutral graphite ground, steel-blue accent.
  static const AppColors slateColors = AppColors(
    background: Color(0xFF0A0B0D),
    surface: Color(0xFF101216),
    surfaceElevated: Color(0xFF17191E),
    surfaceHigh: Color(0xFF1F2229),
    outline: Color(0xFF262A32),
    outlineSoft: Color(0xFF1B1E24),
    primary: Color(0xFF759EF0),
    primaryDim: Color(0xFF2C5DBE),
    onPrimary: Color(0xFF0A0B0D),
    success: _darkSuccess,
    warn: _darkWarn,
    info: _darkInfo,
    onSurface: Color(0xFFD9E0ED),
    onSurfaceMuted: Color(0xFFA9AEB8),
    onSurfaceFaint: Color(0xFF6E7582),
    shadow: _darkShadow,
    foundWord: _darkFoundWord,
    foundWordFlash: _foundWordFlash,
    regionAccent: _darkRegionAccent,
  );

  /// Pale mint ground, deep teal accent.
  static const AppColors morningMintColors = AppColors(
    background: Color(0xFFF2F8F7),
    surface: Color(0xFFF9FDFD),
    surfaceElevated: Color(0xFFE7F1EF),
    surfaceHigh: Color(0xFFDBE8E5),
    outline: Color(0xFFB7CBC7),
    outlineSoft: Color(0xFFD0E0DD),
    primary: Color(0xFF187C79),
    primaryDim: Color(0xFF41AAA7),
    onPrimary: Color(0xFFF9FDFD),
    success: _lightSuccess,
    warn: _lightWarn,
    info: _lightInfo,
    onSurface: Color(0xFF141E20),
    onSurfaceMuted: Color(0xFF445255),
    onSurfaceFaint: Color(0xFF6E7F82),
    shadow: _lightShadow,
    foundWord: _lightFoundWord,
    foundWordFlash: _foundWordFlash,
    regionAccent: _lightRegionAccent,
  );

  /// Warm sand ground, terracotta accent.
  static const AppColors desertSandColors = AppColors(
    background: Color(0xFFFBF4EF),
    surface: Color(0xFFFFFBF8),
    surfaceElevated: Color(0xFFF5EBE2),
    surfaceHigh: Color(0xFFEEE0D5),
    outline: Color(0xFFD4BFAE),
    outlineSoft: Color(0xFFE7D6C9),
    primary: Color(0xFFAE5337),
    primaryDim: Color(0xFFC08D7E),
    onPrimary: Color(0xFFFFFBF8),
    success: _lightSuccess,
    warn: _lightWarn,
    info: _lightInfo,
    onSurface: Color(0xFF201814),
    onSurfaceMuted: Color(0xFF554A44),
    onSurfaceFaint: Color(0xFF82756E),
    shadow: _lightShadow,
    foundWord: _lightFoundWord,
    foundWordFlash: _foundWordFlash,
    regionAccent: _lightRegionAccent,
  );

  /// Every palette by name, so a test can walk all of them and the Style
  /// Gallery can show all of them without either one keeping its own list
  /// that could fall behind this file.
  ///
  /// A `switch` rather than a map so that adding an [AppThemeVariant] without
  /// a palette here is a compile error.
  static AppColors colorsFor(AppThemeVariant variant) => switch (variant) {
    AppThemeVariant.midnight => darkColors,
    AppThemeVariant.deepSea => deepSeaColors,
    AppThemeVariant.twilight => twilightColors,
    AppThemeVariant.forest => forestColors,
    AppThemeVariant.slate => slateColors,
    AppThemeVariant.daylight => lightColors,
    AppThemeVariant.morningMint => morningMintColors,
    AppThemeVariant.desertSand => desertSandColors,
  };

  /// The tokens for one look. [AppThemeVariant.isDark] is where the domain's
  /// flutter-free bool becomes a [Brightness] — the one place the translation
  /// happens, so a variant and its brightness cannot disagree.
  static AppTokens forVariant(AppThemeVariant variant) => AppTokens(
    colors: colorsFor(variant),
    brightness: variant.isDark ? Brightness.dark : Brightness.light,
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
