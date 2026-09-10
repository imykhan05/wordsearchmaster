/// Every one-shot sound the game can play. One entry per file under
/// `assets/audio/`.
///
/// FLAT, NOT PER-THEME. Until the player-supplied audio pass this was
/// `assets/audio/{theme.id}/`, with three synthesized sets a player chose
/// between in Settings. That picker is gone: there is now ONE sound design,
/// made of real recordings rather than generated tones, so a folder level
/// that existed only to hold alternatives had nothing left to hold.
enum AudioClip {
  /// A correctly traced word. The only clip ever played at anything other
  /// than its natural pitch — see `ComboPitchLadder`.
  found,

  /// A traced run that matched nothing.
  ///
  /// Ch03 originally specified SILENCE here — the wrong-selection feedback
  /// was the capsule's 180ms fade and nothing else, so that a miss never
  /// felt like a scolding. The player asked for an audible cue directly, so
  /// that call is deliberately reversed; the fade is untouched and this
  /// plays alongside it. It is mixed well below [levelComplete] for the same
  /// reason the original rule existed: a miss should register, not sting.
  wrong,

  /// A journey level finished. The longest clip in the set at ~3.9s, which
  /// is the player's own explicit choice: they supplied this recording a
  /// second time specifically to say it belonged on level complete rather
  /// than on the Daily, where it had first landed.
  levelComplete,

  /// The Daily Challenge's own finish, distinct from an ordinary level's.
  /// Shorter than [levelComplete] since the two swapped places — still its
  /// own sound, so the once-a-day moment never sounds like an ordinary one.
  dailyComplete,

  chestOpen,

  buttonTap,

  /// Advancing to the next level from the level-complete card. A movement
  /// sound rather than a click, because something is being left behind.
  transition,

  /// The 180° board flip (the rotate button).
  shuffle,

  coin;

  String get assetPath => 'audio/${_fileNames[this]}';

  static const Map<AudioClip, String> _fileNames = {
    AudioClip.found: 'found.mp3',
    AudioClip.wrong: 'wrong.mp3',
    AudioClip.levelComplete: 'level_complete.mp3',
    AudioClip.dailyComplete: 'daily_complete.mp3',
    AudioClip.chestOpen: 'chest_open.mp3',
    AudioClip.buttonTap: 'button_tap.mp3',
    AudioClip.transition: 'transition.mp3',
    AudioClip.shuffle: 'shuffle.mp3',
    AudioClip.coin: 'coin.mp3',
  };
}
