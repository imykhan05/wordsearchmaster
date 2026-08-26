/// The five Ch03 sound effects. One entry per file under `assets/audio/`.
enum AudioClip {
  /// A correctly traced word. The only clip ever played at anything other
  /// than its natural pitch — see `ComboPitchLadder`.
  found,

  levelComplete,

  /// Not yet wired to any UI — the chest/reward screen is P15/P16 territory
  /// — but Ch03 asks for the clip now so that prompt only has to call
  /// `playChestOpen()`, never touch the audio layer itself.
  chestOpen,

  buttonTap,

  coin;

  String get assetPath => 'audio/${_fileNames[this]}';

  static const Map<AudioClip, String> _fileNames = {
    AudioClip.found: 'found.wav',
    AudioClip.levelComplete: 'level_complete.wav',
    AudioClip.chestOpen: 'chest_open.wav',
    AudioClip.buttonTap: 'button_tap.wav',
    AudioClip.coin: 'coin.wav',
  };
}
