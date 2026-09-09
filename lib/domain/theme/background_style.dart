/// What sits behind the board (competitor-driven polish, post-P18).
///
/// `docs/competitor-analysis.md`'s recording shows every competitor floating
/// the grid and word list as opaque cards over a full-screen scene. This is
/// that, plus the one thing they do not offer: the player's OWN photo.
///
/// PURE DART — no `package:flutter` import, so this file names no colour. The
/// three gradients are [gradientIndex] into `AppColors.backgroundGradients`,
/// which is the same indirection `JourneyRegion` already uses for its accent
/// (CLAUDE.md P11: "a region knows its ACCENT INDEX, never a `Color`"). It is
/// also what lets both themes define their own version of "ember" without this
/// enum knowing either exists.
///
/// [id] is BOTH the persisted preference string and the enum's identity, the
/// same one-string-one-truth rule `SoundTheme` keeps.
enum BackgroundStyle {
  /// Default: a quiet wash from the page colour into the highest surface
  /// tint. Closest to the flat ground the app shipped with, so an existing
  /// player's screen does not change under them on upgrade.
  calm('calm', gradientIndex: 0),

  /// Warm — the amber primary bled into the ground, brightest at the bottom.
  ember('ember', gradientIndex: 1),

  /// Cool — the map's first region accent, same treatment.
  lagoon('lagoon', gradientIndex: 2),

  /// A photo the player picked from their own phone.
  ///
  /// The image itself is NOT part of this value: it lives on disk and its
  /// path is stored separately (`UiSettingsStore.backgroundPhotoPath`),
  /// because a photo can go missing on its own — the OS may evict the cache
  /// directory it sits in at any time. When it does, [gradientIndex] is what
  /// this style falls back to, which is why `photo` carries one at all: the
  /// background degrades to [calm]'s gradient rather than to a blank screen
  /// or an error the player never asked to see.
  photo('photo', gradientIndex: 0);

  const BackgroundStyle(this.id, {required this.gradientIndex});

  final String id;

  /// Which entry of `AppColors.backgroundGradients` this style paints — and,
  /// for [photo], what it falls back to when the file is gone.
  final int gradientIndex;

  static const BackgroundStyle defaultStyle = BackgroundStyle.calm;

  /// The three gradient styles, in the order a picker should offer them.
  /// [photo] is excluded: it is not a swatch, it is a file chooser, and the
  /// UI presents it as its own action.
  static List<BackgroundStyle> get gradients =>
      values.where((style) => style != BackgroundStyle.photo).toList();

  /// Falls back to [defaultStyle] for an unrecognised id — the same
  /// degrade-don't-throw shape `SoundTheme.fromId` uses, for the same reason
  /// (a downgrade, or a style retired in a later release).
  static BackgroundStyle fromId(String? id) =>
      values.firstWhere((style) => style.id == id, orElse: () => defaultStyle);
}
