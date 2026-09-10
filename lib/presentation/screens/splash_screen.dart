import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/language/selected_language.dart';
import '../../app/theme/theme.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/app_background.dart';

/// The very first screen any launch shows — [SplashRoute], always the
/// router's `initialLocation`.
///
/// PLAYER-REQUESTED, and requested WITH a concrete shape: the app's name
/// centred, the brand icon at the bottom, and the background music already
/// playing underneath it. The last of those needs no wiring here at all —
/// `musicSync` (`services/audio/audio_service.dart`) is watched once at the
/// app root and fires the instant `WordSearchMasterApp` builds, which is
/// BEFORE this screen's own first frame, so the bed is already running by
/// the time a player sees the wordmark.
///
/// This is also the ONE place `hasChosenLanguageProvider` is read now —
/// see `router.dart`'s header for why moving it here, out of the router
/// itself, is a strict improvement over the shape it replaced.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// How long the brand stays on screen, start to hand-off. ONE controller
  /// drives the WHOLE window — deliberately not a separate `Timer` alongside
  /// a shorter entrance animation, which was the first version of this file
  /// and was wrong: once the entrance settled, nothing was left scheduling
  /// frames for the remaining hold, so `pumpAndSettle()` — which stops the
  /// instant no frame is scheduled, not when every pending `Timer` has fired
  /// — returned control early, before the hand-off timer ever got a chance
  /// to run. Every existing test that pumps the real app root learned that
  /// the hard way (`app_smoke_test.dart` and siblings). A single controller
  /// ticking for the full duration keeps a frame scheduled throughout, which
  /// is what makes `pumpAndSettle()` behave here the same way it already
  /// does on every other P09/P11 choreography screen in this app.
  ///
  /// Independent of reduce-motion on purpose: this is a branding BEAT, not a
  /// movement, so [_reduceMotion] below skips the entrance TRANSFORM but
  /// never shortens this duration — a player who asked for less motion still
  /// needs a moment to register the screen, the same distinction
  /// `_PulseHighlight` draws between "remove the movement" and "remove the
  /// information".
  static const Duration _displayDuration = Duration(milliseconds: 1600);

  /// Sub-ranges of the controller's own `value`, not a separate clock: the
  /// icon leads, the name follows with a stagger, and both sit fully
  /// revealed for the remaining ~700ms before hand-off — the same "one
  /// driver, several `Interval`s" shape `LevelCompleteCard`'s confetti and
  /// `ChestOpenCard` already use (P09/P11) rather than a second ticker
  /// system for what is really one animation.
  static const Interval _iconReveal = Interval(0.0, 0.4);
  static const Interval _nameReveal = Interval(0.2, 0.55);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _displayDuration)
      ..addStatusListener(_onStatusChanged)
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _proceed();
  }

  /// One-shot, like every other post-timer navigation in this app —
  /// guarded by [mounted] because a player can back out (or a test can tear
  /// the tree down) before the controller ever completes.
  ///
  /// Reads [hasChosenLanguageProvider] rather than watching it: this widget
  /// is about to navigate away and never rebuild, so a watch would only cost
  /// a subscription this screen will not live long enough to use.
  void _proceed() {
    if (!mounted) return;
    final returning = ref.read(hasChosenLanguageProvider);
    context.go(
      returning ? const HomeRoute().location : const LanguageRoute().location,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final language = ref.watch(selectedLanguageProvider);
    // Reduce-motion SKIPS the entrance outright rather than collapsing it to
    // an instantaneous version of itself — the same rule particles, confetti
    // and the FTUE glow already follow (P09/P11/P12), applied here for the
    // identical reason: a fade-in-then-immediately-fade-out on a single
    // frame is not what "reduced motion" is asking for.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AppBackground(
      child: Scaffold(
        // Transparent so the chosen background shows through, matching every
        // other `AppBackground`-using screen — see its own header for why a
        // Scaffold's default opaque fill would hide it.
        backgroundColor: tokens.colors.background.withValues(alpha: 0),
        body: SafeArea(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final iconT = reduceMotion
                  ? 1.0
                  : _iconReveal.transform(_controller.value);
              final nameT = reduceMotion
                  ? 1.0
                  : _nameReveal.transform(_controller.value);

              return Column(
                children: [
                  const Spacer(flex: 3),
                  Opacity(
                    key: const Key('splashNameOpacity'),
                    opacity: nameT,
                    child: Transform.translate(
                      offset: Offset(0, (1 - nameT) * 16),
                      child: Text(
                        l10n.appTitle,
                        textAlign: TextAlign.center,
                        style: AppTypography.uiTextStyle(
                          language,
                          UiRole.display,
                          color: tokens.colors.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(flex: 4),
                  Opacity(
                    key: const Key('splashIconOpacity'),
                    opacity: iconT,
                    child: Transform.scale(
                      scale: 0.7 + (0.3 * iconT),
                      child: _SplashIcon(tokens: tokens),
                    ),
                  ),
                  const SizedBox(height: AppTokens.space48),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The brand mark: the same PNG the Play Store listing and the Android/iOS
/// launcher icons already use (`docs/store-listing/assets/icon_512.png`,
/// bundled as `assets/branding/app_icon.png`), framed with the app's own
/// elevation token rather than a bespoke shadow — the same treatment
/// `MetaCard` gives every other elevated surface in this app.
class _SplashIcon extends StatelessWidget {
  const _SplashIcon({required this.tokens});

  final AppTokens tokens;

  static const double _size = 112;

  @override
  Widget build(BuildContext context) {
    final elevation = tokens.elevation2;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppTokens.borderRadius16,
        boxShadow: elevation.shadows,
      ),
      child: ClipRRect(
        borderRadius: AppTokens.borderRadius16,
        child: Image.asset(
          'assets/branding/app_icon.png',
          width: _size,
          height: _size,
        ),
      ),
    );
  }
}
