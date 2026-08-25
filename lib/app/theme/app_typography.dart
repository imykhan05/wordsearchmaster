import 'package:flutter/material.dart';

import '../../domain/text/language.dart';

/// Bundled font families. These strings must match the `family:` keys in
/// `pubspec.yaml`. Fonts are shipped as assets, never taken from the device —
/// many budget Android phones in PK/IN have no Urdu font at all, and the
/// result is a grid of tofu boxes and a one-star review (Ch04).
abstract final class AppFonts {
  /// Horizontal, balanced, and sits square in a cell — the ONLY correct
  /// choice for Urdu grid letters.
  static const String naskh = 'NotoNaskhArabic';

  /// What Urdu is *supposed* to look like to a native reader — but it is
  /// calligraphic and steeply sloped, so it belongs in headings and word
  /// chips, never inside a grid cell.
  static const String nastaliq = 'NotoNastaliqUrdu';

  static const String devanagari = 'NotoSansDevanagari';

  /// Latin sans. Noto Sans keeps I/l and O/0 distinguishable, which matters
  /// in a grid where a single glyph must be identified out of context.
  static const String latin = 'NotoSans';
}

/// Where a piece of UI text sits in the hierarchy. Drives both size and, for
/// Urdu, whether Nastaliq is allowed.
enum UiRole {
  /// Screen-owning titles and celebratory numbers.
  display,

  /// Section headings.
  heading,

  /// Card titles, list-row titles.
  title,

  /// Running text.
  body,

  /// Buttons, chips, tabs.
  label,

  /// Secondary metadata.
  caption,

  /// A target word in the word-list panel.
  ///
  /// Display-class on purpose: the word is large, decorative, and read as a
  /// whole word in its connected form — exactly what Nastaliq is for. This is
  /// the shape the player maps onto the isolated letters in the grid, so it
  /// must look like real Urdu (Ch04).
  wordChip,
}

/// Font/size/height decisions per script. Every text style in the app comes
/// from here — no widget builds its own [TextStyle] from scratch.
abstract final class AppTypography {
  /// Roles that may render in Nastaliq, and only for [Language.urdu].
  /// Enforced by `gridTextStyle` never consulting this set at all, and by
  /// `test/app/theme/typography_test.dart`.
  static const Set<UiRole> nastaliqRoles = {
    UiRole.display,
    UiRole.heading,
    UiRole.wordChip,
  };

  /// Fallback cell size used when a caller has not measured the grid yet.
  /// P06 passes the real measured cell size.
  static const double defaultGridCellSize = 40;

  /// Grid cells opt OUT of system text scaling: the grid has its own scaling
  /// (cell size drives glyph size), and letting the OS scale it on top would
  /// overflow cells. Everything else in the app respects the system scale.
  ///
  /// Render grid text with `Text(..., textScaler: AppTypography.gridTextScaler)`
  /// or, in P06's painter, by not applying a scaler at all.
  static const TextScaler gridTextScaler = TextScaler.noScaling;

  /// The style for a single grid cell.
  ///
  /// Never returns [AppFonts.nastaliq]. Urdu grid letters are rendered as
  /// isolated forms in Naskh — that is the correct convention for a printed
  /// word search, not a bug (Ch04, Masla 1).
  static TextStyle gridTextStyle(
    Language language, {
    double cellSize = defaultGridCellSize,
    Color? color,
    FontWeight weight = FontWeight.w500,
  }) {
    final metrics = _gridMetrics(language);
    return TextStyle(
      fontFamily: metrics.family,
      fontSize: cellSize * metrics.sizeFactor,
      height: metrics.height,
      fontWeight: weight,
      color: color,
      // Cells are single graphemes; letter spacing would only shift them off
      // centre inside the cell.
      letterSpacing: 0,
    );
  }

  /// The style for UI text in [role], for [language].
  static TextStyle uiTextStyle(
    Language language,
    UiRole role, {
    Color? color,
    FontWeight? weight,
  }) {
    final metrics = _roleMetrics(role);
    final family = _uiFamily(language, role);

    // Nastaliq's tall ascenders and deep descenders need noticeably more
    // leading than a Latin or Devanagari face at the same size.
    final isNastaliq = family == AppFonts.nastaliq;
    final height = isNastaliq ? metrics.height * 1.55 : metrics.height;

    return TextStyle(
      fontFamily: family,
      fontSize: metrics.size,
      height: height,
      fontWeight: weight ?? metrics.weight,
      color: color,
      letterSpacing: language == Language.english ? metrics.letterSpacing : 0,
    );
  }

  /// The family used for grid cells in [language]. Never Nastaliq.
  static String gridFontFamily(Language language) =>
      _gridMetrics(language).family;

  /// The family used for UI text in [language] at [role].
  ///
  /// Defaults to [UiRole.body], which is the *body-class* family — Naskh for
  /// Urdu, not Nastaliq. Display-class roles opt into Nastaliq by passing
  /// their own role.
  static String uiFontFamily(Language language, {UiRole role = UiRole.body}) =>
      _uiFamily(language, role);

  /// The UI font family for [language] in [role]. Nastaliq only for Urdu, and
  /// only in [nastaliqRoles].
  static String _uiFamily(Language language, UiRole role) {
    return switch (language) {
      Language.urdu =>
        nastaliqRoles.contains(role) ? AppFonts.nastaliq : AppFonts.naskh,
      Language.hindi => AppFonts.devanagari,
      Language.english => AppFonts.latin,
    };
  }

  static _GridMetrics _gridMetrics(Language language) {
    return switch (language) {
      // Naskh sits comfortably at most of the cell height.
      Language.urdu => const _GridMetrics(
        family: AppFonts.naskh,
        sizeFactor: 0.56,
        height: 1.30,
      ),
      // Devanagari aksharas carry matras above and below the baseline, so the
      // glyph gets a smaller box and more leading to stay inside the cell.
      Language.hindi => const _GridMetrics(
        family: AppFonts.devanagari,
        sizeFactor: 0.48,
        height: 1.45,
      ),
      Language.english => const _GridMetrics(
        family: AppFonts.latin,
        sizeFactor: 0.52,
        height: 1.20,
      ),
    };
  }

  static _RoleMetrics _roleMetrics(UiRole role) {
    return switch (role) {
      UiRole.display => const _RoleMetrics(
        size: 32,
        height: 1.15,
        weight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      UiRole.heading => const _RoleMetrics(
        size: 24,
        height: 1.22,
        weight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
      UiRole.title => const _RoleMetrics(
        size: 18,
        height: 1.30,
        weight: FontWeight.w600,
        letterSpacing: 0,
      ),
      UiRole.body => const _RoleMetrics(
        size: 15,
        height: 1.50,
        weight: FontWeight.w400,
        letterSpacing: 0,
      ),
      UiRole.label => const _RoleMetrics(
        size: 14,
        height: 1.30,
        weight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      UiRole.caption => const _RoleMetrics(
        size: 12,
        height: 1.40,
        weight: FontWeight.w400,
        letterSpacing: 0.25,
      ),
      UiRole.wordChip => const _RoleMetrics(
        size: 20,
        height: 1.30,
        weight: FontWeight.w600,
        letterSpacing: 0.25,
      ),
    };
  }
}

@immutable
final class _GridMetrics {
  const _GridMetrics({
    required this.family,
    required this.sizeFactor,
    required this.height,
  });

  final String family;

  /// Glyph size as a fraction of the cell's side.
  final double sizeFactor;
  final double height;
}

@immutable
final class _RoleMetrics {
  const _RoleMetrics({
    required this.size,
    required this.height,
    required this.weight,
    required this.letterSpacing,
  });

  final double size;
  final double height;
  final FontWeight weight;
  final double letterSpacing;
}
