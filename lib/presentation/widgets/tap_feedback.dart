import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/audio/audio_service.dart';
import '../../services/haptics/haptics_service.dart';

/// Ch03's `button_tap`: the click and the light tick a control gives back the
/// moment it is pressed.
///
/// ONE CALL PER CONTROL, and it exists because the alternative was tried and
/// did not hold. P09 wired the pair inline — three lines of
/// `read(audioServiceProvider).playButtonTap()` +
/// `read(hapticsServiceProvider).buttonTap()` at each site — and by the time
/// the app reached a device, 5 of roughly 65 interactive controls had it.
/// The player found the gaps immediately and named two of them (the AppBar
/// back arrow and "Continue with Google"). A three-line idiom that has to be
/// remembered at every new button is a rule nobody can keep; a one-line one
/// at least fails visibly, because a handler without it reads as different
/// from every handler around it.
///
/// A GLOBAL LISTENER WOULD BE BETTER STILL, AND FLUTTER DOES NOT ALLOW IT.
/// The obvious structural fix is one `Listener` at the app root that plays
/// the click whenever a pointer lands on something tappable, which would
/// cover every present and future control with nothing to remember. It was
/// prototyped and abandoned on evidence: the hit-test path of an ENABLED
/// `ElevatedButton` and a DISABLED one are identical, render object for
/// render object, because `InkResponse` builds its inner `GestureDetector`
/// with `excludeFromSemantics: true` and its enabled-ness lives only in
/// callbacks the path does not expose. So a root listener could not tell a
/// live button from a greyed-out one, and would have clicked at both — a
/// worse bug than the one it fixed. Reading it back out would mean
/// `@protected` framework API or matching private class names, neither of
/// which survives a Flutter upgrade.
///
/// Deliberately NOT applied to: the grid itself (P06 owns its own selection
/// tick), the rotate button and the level-complete "Continue" (each has its
/// own sound — see `AudioClip.shuffle`/`AudioClip.transition`), and every
/// dev-only surface (the debug panel, the Sync Inspector, the Style
/// Gallery), which no player can reach.
extension TapFeedback on WidgetRef {
  /// Plays the click and fires the tick. Safe to call from any handler: both
  /// services are no-ops when their toggle is off, and neither awaits.
  void tapFeedback() {
    read(audioServiceProvider).playButtonTap();
    read(hapticsServiceProvider).buttonTap();
  }
}
