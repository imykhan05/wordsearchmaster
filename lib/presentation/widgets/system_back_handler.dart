import 'package:flutter/widgets.dart';

/// Gives the Android system back button (and the back gesture) somewhere to go
/// on a screen reached through go_router's `.go()`.
///
/// ---------------------------------------------------------------------------
/// WHY THIS EXISTS
///
/// Every forward navigation in this app is a `.go()`, which REPLACES the
/// route stack rather than pushing onto it. That is deliberate — the app is a
/// hub and a set of one-deep screens, and pushing would let a player stack
/// Home → Journey → Game → Home → … without bound.
///
/// The cost is that the Navigator has nothing to pop. Android's back button
/// asks the Navigator first, gets "nothing here", and hands the event to the
/// OS, which closes the app. From the player's side the game simply
/// disappears mid-level — reported from a real device as "back pe game hi
/// band ho jata hai".
///
/// A `PopScope` that never pops and routes explicitly instead is the fix. It
/// is a widget rather than a mixin so a screen opts in by wrapping its body,
/// with no base class to inherit and nothing to remember to call.
///
/// [onBack] does the navigating itself, because several screens have work to
/// do first — the game screen records an abandon (P12) before it leaves.
class SystemBackHandler extends StatelessWidget {
  const SystemBackHandler({
    required this.onBack,
    required this.child,
    super.key,
  });

  /// Runs when the system back is pressed. Must navigate: nothing else will.
  final VoidCallback onBack;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Never let the framework pop. On a `.go()` route there is no previous
      // entry, so a pop that "succeeds" is the app closing.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // `didPop` true would mean something else already handled it — a
        // modal route above this screen, say. Only act on the case where the
        // event reached us unhandled.
        if (didPop) return;
        onBack();
      },
      child: child,
    );
  }
}
