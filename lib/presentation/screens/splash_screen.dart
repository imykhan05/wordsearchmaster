import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/language/selected_language.dart';
import '../../app/theme/theme.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';

/// The very first screen any launch shows — [SplashRoute], always the
/// router's `initialLocation`.
///
/// PLAYER-SUPPLIED art now carries the whole scene:
/// `assets/branding/splash_background.png`, a parchment-and-quill
/// illustration with the wordmark and two decorative word-search grids
/// painted directly into it. This screen no longer renders its own name —
/// the artwork already has one — and no longer wraps in `AppBackground`,
/// because that widget paints the player's chosen in-game theme, and this
/// is a fixed piece of branding shown before any theme has even loaded.
///
/// The one thing this screen still renders itself is the "LOADING… NN%"
/// readout: a real percentage has to be live, so it is drawn on top of the
/// artwork in the same spot and style its own mock-up used, in ink-brown
/// sampled straight from that art ([SplashInkPalette]) rather than the app's
/// in-game marigold — a colour choice this ONE screen makes and no other
/// screen should copy.
///
/// The background music needs no wiring here at all — `musicSync`
/// (`services/audio/audio_service.dart`) is watched once at the app root and
/// fires the instant `WordSearchMasterApp` builds, which is BEFORE this
/// screen's own first frame, so the bed is already running by the time a
/// player sees the wordmark.
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
  /// drives the WHOLE window — deliberately not a separate `Timer`, because
  /// `pumpAndSettle()` stops the instant no frame is scheduled, not when
  /// every pending `Timer` has fired; a controller ticking for the full
  /// duration keeps a frame scheduled throughout, which is what every test
  /// that pumps the real app root (`app_smoke_test.dart` and siblings)
  /// depends on.
  ///
  /// PLAYER-REQUESTED at 15–20s so the screen reads as a real load (a
  /// progress bar filling), not an instant brand flash. Picked the middle of
  /// that range.
  static const Duration _displayDuration = Duration(seconds: 18);

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
    final language = ref.watch(selectedLanguageProvider);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/branding/splash_background.png',
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // AnimationController defaults its bounds to [0.0, 1.0], so
                // `.value` is already the fill fraction the bar needs. Not
                // gated by reduce-motion: this is the load state itself, not
                // decorative movement, so it keeps advancing in real time
                // regardless — the same information-vs-motion split
                // `_PulseHighlight` (`game_grid.dart`) draws.
                final progress = _controller.value;

                return Column(
                  // STRETCH so the progress bar below actually gets a
                  // bounded width to size its fill against — see
                  // `_SplashProgress`'s own comment on the same need.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(flex: 7),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.space32,
                      ),
                      child: _SplashProgress(
                        progress: progress,
                        loadingLabel: l10n.splashLoading,
                        language: language,
                      ),
                    ),
                    const Spacer(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The "game is loading" readout: an upper-case caption, the solid bar, then
/// the percentage — positioned and coloured to match where the reference
/// mock-up drew them directly into the artwork, now live instead of static.
class _SplashProgress extends StatelessWidget {
  const _SplashProgress({
    required this.progress,
    required this.loadingLabel,
    required this.language,
  });

  final double progress;
  final String loadingLabel;
  final Language language;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round();
    final captionStyle = AppTypography.uiTextStyle(
      language,
      UiRole.label,
      color: SplashInkPalette.fill,
    ).copyWith(fontSize: 15);
    final percentStyle = AppTypography.uiTextStyle(
      language,
      UiRole.heading,
      color: SplashInkPalette.fill,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    return Column(
      mainAxisSize: MainAxisSize.min,
      // STRETCH, not the default `center`: `_SolidProgressBar` needs an
      // actual width from its parent to size its fill against — a
      // shrink-wrapped Column gives it none, since nothing else in this
      // column has an intrinsic width to shrink-wrap to either.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // toUpperCase() is a display transform, not new copy — a no-op on
        // Urdu/Hindi, which have no case distinction.
        Text(
          '${loadingLabel.toUpperCase()}…',
          textAlign: TextAlign.center,
          style: captionStyle,
        ),
        const SizedBox(height: AppTokens.space12),
        _SolidProgressBar(progress: progress),
        const SizedBox(height: AppTokens.space12),
        Text('$percent%', textAlign: TextAlign.center, style: percentStyle),
      ],
    );
  }
}

/// The plain, solid-fill pill from the reference artwork — a rounded ink
/// bar over a parchment track, unlike the striped bar an earlier version of
/// this screen used before this specific mock-up was supplied.
class _SolidProgressBar extends StatelessWidget {
  const _SolidProgressBar({required this.progress});

  final double progress;

  static const double _height = 14;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(_height / 2);

    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: SplashInkPalette.track,
        borderRadius: radius,
        border: Border.all(color: SplashInkPalette.border),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: progress,
            child: const DecoratedBox(
              decoration: BoxDecoration(color: SplashInkPalette.fill),
            ),
          ),
        ),
      ),
    );
  }
}
