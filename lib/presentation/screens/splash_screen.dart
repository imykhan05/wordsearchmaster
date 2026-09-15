import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/theme.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';

/// The very first thing any launch paints, and — since it now runs BEFORE
/// there is a `ProviderScope` — the one screen in this app that reads no
/// provider at all.
///
/// ---------------------------------------------------------------------------
/// WHY THIS IS NOT A ROUTED SCREEN ANY MORE
///
/// It used to be `SplashRoute`, the router's `initialLocation`, holding for a
/// fixed 18s (later 3s) on an `AnimationController`. Two things were wrong
/// with that, and they were the same thing twice:
///
///  * The bar was never a load. It filled on a timer, so it reached 100%
///    whether the app was ready or not — and the player waited out whatever
///    the number happened to be set to, on top of the real startup.
///  * Nothing was on screen during the startup it claimed to be showing.
///    `bootstrap` awaited every init step before `runApp`, so the actual wait
///    — Firebase, App Check, sign-in, the database, the content pack — was
///    spent on a blank window, and this screen only appeared once all of it
///    had already finished.
///
/// So it moved in front of `runApp` ([BootGate], `app/bootstrap.dart`). It is
/// mounted within a frame of process start, it shows the real init running
/// behind it, and it hands off the moment that init is done. The visible wait
/// is now exactly startup, once, instead of startup followed by a timer.
///
/// [progressCeiling] is the honesty rule: the bar eases toward it while work
/// is outstanding and only crosses it once [ready] has actually resolved, so
/// 100% never means anything except "the app is up".
///
/// ---------------------------------------------------------------------------
/// PLAYER-SUPPLIED art carries the whole scene:
/// `assets/branding/splash_background.png`, a parchment-and-quill
/// illustration with the wordmark and two decorative word-search grids
/// painted directly into it. This screen renders no name of its own — the
/// artwork already has one — and does not wrap in `AppBackground`, which
/// paints the player's chosen in-game theme; this is fixed branding shown
/// before a theme (or a database to read one from) exists.
///
/// The "LOADING… NN%" readout is drawn in ink-brown sampled straight from
/// that art ([SplashInkPalette]) rather than the app's in-game marigold — a
/// colour choice this ONE screen makes and no other screen should copy.
class BootSplash extends StatefulWidget {
  const BootSplash({
    required this.ready,
    required this.onFinished,
    this.language = Language.english,
    super.key,
  });

  /// Startup itself. The hand-off waits on this, never on a clock.
  final Future<void> ready;

  /// Fired once — [ready] has resolved AND the bar has actually arrived at
  /// 100%, so the player never sees the screen cut away mid-fill.
  final VoidCallback onFinished;

  /// Typography only. Defaults to English because the stored choice lives in
  /// the settings store, which is part of the very startup this screen is
  /// waiting on — there is nothing else it could honestly use yet.
  final Language language;

  /// How far the bar may fill on the timer alone. Past this point it is
  /// waiting on [ready], not on time.
  static const double progressCeiling = 0.9;

  /// How long the bar takes to ease up to [progressCeiling]. Not a hold: if
  /// startup outlasts it the bar simply sits there, and if startup finishes
  /// first the remaining fill still runs, which is what keeps a fast launch
  /// from flashing past too fast to read.
  static const Duration fillDuration = Duration(milliseconds: 1400);

  /// The last stretch, [progressCeiling] to 1.0, once startup is done.
  static const Duration finishDuration = Duration(milliseconds: 260);

  @override
  State<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<BootSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: BootSplash.fillDuration,
    )..addStatusListener(_onStatusChanged);
    // Drives 0 -> progressCeiling. The rest is only reachable from [_finish].
    _controller.animateTo(
      BootSplash.progressCeiling,
      duration: BootSplash.fillDuration,
      curve: Curves.easeOutCubic,
    );
    unawaited(_awaitReady());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Startup may finish before, during or after the fill — all three end the
  /// same way, because the finishing animation always runs from wherever the
  /// bar currently is.
  Future<void> _awaitReady() async {
    try {
      await widget.ready;
    } catch (_) {
      // A failed startup is still a startup: `initializeServices` never
      // throws (every step is caught), and if something upstream ever did,
      // stranding the player on a splash forever is the one response that
      // helps nobody. Carry on and let the app show whatever state it is in.
    }
    if (!mounted) return;
    await _controller.animateTo(
      1,
      duration: BootSplash.finishDuration,
      curve: Curves.easeOut,
    );
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    // `animateTo(progressCeiling)` also reports `completed`, so the value is
    // what decides, not the status alone.
    if (_controller.value < 1) return;
    if (_handedOff) return;
    _handedOff = true;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = widget.language;

    return Scaffold(
      // The parchment tone of the artwork itself, so the very first painted
      // frame is already the right colour. Decoding the image takes a frame
      // or two, and the default Material white behind it would read as a
      // flash at the exact moment this screen exists to make calm.
      backgroundColor: SplashInkPalette.track,
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
        _FillingCaption(
          text: '${loadingLabel.toUpperCase()}…',
          progress: progress,
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

/// The word "LOADING…" inking itself in as the app comes up — the same
/// progress the bar and the percentage are already showing, on the third
/// element of the readout that was sitting there static.
///
/// A [ShaderMask] with a HARD STOP rather than two stacked `Text`s clipped
/// against each other: the two-Text approach has to lay the string out
/// twice, in perfect register, and any disagreement between the two (a
/// rounding difference in centring, a font falling back on one and not the
/// other) shows up as a visible seam down the middle of a letter. One text,
/// one layout, a mask over it — the edge lands mid-glyph by construction and
/// cannot drift.
///
/// The mask spans the TEXT's own box, not the row's full width, which is why
/// the caller centres it rather than letting the stretched `Column` hand it
/// the whole line. Across the full width the word — narrower, centred —
/// would sit untouched until progress reached its left edge and then finish
/// well before 100%, which is precisely the thing it is here to stop doing.
///
/// Fills along the READING direction, so Urdu inks right to left.
class _FillingCaption extends StatelessWidget {
  const _FillingCaption({
    required this.text,
    required this.progress,
    required this.style,
  });

  final String text;
  final double progress;
  final TextStyle style;

  /// The ink still to come. Same hue, so the word reads as one word being
  /// filled rather than two colours of text.
  static final Color _unfilled = SplashInkPalette.fill.withValues(alpha: 0.28);

  @override
  Widget build(BuildContext context) {
    final filled = progress.clamp(0.0, 1.0);
    final leftToRight = Directionality.of(context) == TextDirection.ltr;

    return Center(
      child: ShaderMask(
        // srcIn paints the shader THROUGH the glyphs, so the letter shapes
        // are the mask and the gradient only decides their colour.
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: leftToRight ? Alignment.centerLeft : Alignment.centerRight,
          end: leftToRight ? Alignment.centerRight : Alignment.centerLeft,
          // Two identical stops at `filled` is what makes this an EDGE
          // rather than a gradient — a smooth ramp would read as the word
          // fading out, not as a level rising through it.
          colors: [
            SplashInkPalette.fill,
            SplashInkPalette.fill,
            _unfilled,
            _unfilled,
          ],
          stops: [0, filled, filled, 1],
        ).createShader(bounds),
        child: Text(text, textAlign: TextAlign.center, style: style),
      ),
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
