/// A curated audio palette (post-competitor-analysis polish, pre-P18).
///
/// `docs/competitor-analysis.md` measured all three competitors converging on
/// one recipe (continuous non-percussive bed + fundamental/octave/fifth bell
/// SFX) but never on letting a PLAYER choose their own sound design — none of
/// them expose more than a Sound/Music on-off pair. So this is deliberately a
/// small, curated set rather than a free-form picker: three hand-designed
/// palettes, not "any 10 sounds a player might assemble." Choice fatigue is
/// a real cost for this app's 45+ audience (CLAUDE.md's own product thesis),
/// and every extra option is also an extra asset bundle on a 2GB-RAM device.
///
/// PURE DART — no `package:flutter` import. The value itself is nothing more
/// than an id; every actual synthesis decision (which partials, how loud,
/// how long the bed's figure runs) lives in `tool/generate_audio_assets.py`,
/// which writes one `assets/audio/{id}/` folder per value here. [id] is used
/// as BOTH the persisted preference string and the asset folder name — one
/// string, one source of truth, so a typo cannot make the stored preference
/// and the shipped folder disagree silently.
enum SoundTheme {
  /// Default, and the shipped answer to the competitor recipe: fundamental +
  /// octave + fifth partials (the harmonic series' own 1x/2x/3x, which is
  /// what a real handbell's partials approximate) on every bell-like SFX,
  /// plus a 5-7kHz shimmer layer on the two celebration clips
  /// (`level_complete`, `chest_open`). The music bed keeps P09's original
  /// mellow pad, only re-voiced with the same 1x/2x/3x structure so the bed
  /// and the SFX read as the same instrument.
  softBells('soft_bells'),

  /// Brighter and busier: the same 1x/2x/3x partial structure but with more
  /// upper-partial energy (a louder 3rd harmonic) and a music bed whose
  /// pentatonic figure moves in shorter, more frequent notes. For a player
  /// who wants the game to feel more alive rather than more calm.
  chimes('chimes'),

  /// The quietest option: fundamental plus a faint 2nd harmonic only (no
  /// 3rd), shorter clips, and a music bed dropped to a near-inaudible
  /// sustained pad with no moving figure at all. For a player who wants
  /// confirmation that something happened and nothing more.
  minimal('minimal');

  const SoundTheme(this.id);

  /// Doubles as `assets/audio/{id}/`'s folder name — see the class doc.
  final String id;

  static const SoundTheme defaultTheme = SoundTheme.softBells;

  /// Falls back to [defaultTheme] for an unrecognised id — the same
  /// degrade-don't-throw shape `UiSettingsStore.selectedLanguage` already
  /// uses for a stored value a newer build no longer recognises (a
  /// downgrade, or a theme retired in a future release).
  static SoundTheme fromId(String? id) => SoundTheme.values.firstWhere(
    (theme) => theme.id == id,
    orElse: () => defaultTheme,
  );
}
