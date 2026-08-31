import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/theme/theme.dart';
import '../../application/game_controller.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/sync_status.dart';

/// Full-screen result card shown while `GameState.phase` is
/// `GamePhase.levelComplete`.
///
/// Stateless: the whole staggered reveal (confetti, stars, then score, then
/// coins) is one [TweenAnimationBuilder] over a single fixed timeline, each
/// piece computing its own local progress from a slice of it — the same
/// shape P06's docs describe for the found-word choreography, just with more
/// slices.
///
/// By the time this shows, [GameController] has already generated the NEXT
/// level behind it (Ch02 Zeigarnik) — [onContinue] is only ever a phase
/// flip, never a new load, so there is nothing to wait for here.
class LevelCompleteCard extends StatelessWidget {
  const LevelCompleteCard({
    required this.summary,
    required this.onContinue,
    this.coinsEarned = 0,
    super.key,
  });

  final LevelCompletionSummary summary;
  final VoidCallback onContinue;

  /// Coins this completion paid out, INCLUDING any chest — resolved by
  /// `ProgressionController` (P11), not by [summary]. `GameController` freezes
  /// gameplay facts only (score, stars, combo); the wallet is a database
  /// concern and async, so `game_screen.dart` awaits the award and passes the
  /// number in here rather than this card reaching into a repository itself.
  final int coinsEarned;

  static const int _starStaggerMs = 140;
  static const int _starPopMs = 140;
  static const int _starsDoneMs = _starStaggerMs * 2 + _starPopMs;
  static const int _scoreRollMs = 400;
  static const int _totalMs = _starsDoneMs + _scoreRollMs;
  static const Duration _totalDuration = Duration(milliseconds: _totalMs);

  /// Confetti pieces to burst. A celebratory flourish, not a gameplay cue —
  /// kept modest for the 2GB-RAM target, same budget-consciousness as
  /// `ParticleLayer`'s 8–12 pieces per found word.
  static const int _confettiCount = 24;

  double _starProgress(double masterT, int index) {
    final startMs = index * _starStaggerMs;
    final localT = ((masterT * _totalMs - startMs) / _starPopMs).clamp(
      0.0,
      1.0,
    );
    return Motion.punch.transform(localT);
  }

  double _scoreProgress(double masterT) {
    final localT = ((masterT * _totalMs - _starsDoneMs) / _scoreRollMs).clamp(
      0.0,
      1.0,
    );
    return Curves.linear.transform(localT);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = AppLocalizations.of(context);
    // Ch03: particles are skipped entirely under reduce-motion, not just
    // sped up — so confetti is never generated at all in that case, the
    // same rule `ParticleLayer`/`FoundWordRevealLayer` apply next door.
    final confetti = MediaQuery.disableAnimationsOf(context)
        ? const <_ConfettiPiece>[]
        : _generateConfetti(
            seed: summary.score ^ summary.stars,
            colors: tokens.colors.foundWord,
          );

    return ColoredBox(
      color: tokens.colors.background.withValues(alpha: 0.96),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: Motion.reduced(context, _totalDuration),
        builder: (context, masterT, child) {
          final scoreT = _scoreProgress(masterT);
          final displayedScore = (summary.score * scoreT).round();
          final displayedCoins = (coinsEarned * scoreT).round();

          return Stack(
            children: [
              if (confetti.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ConfettiPainter(
                        masterT: masterT,
                        pieces: confetti,
                      ),
                    ),
                  ),
                ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppTokens.space24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.levelCompleteTitle,
                          style: AppTypography.uiTextStyle(
                            Language.english,
                            UiRole.display,
                            color: tokens.colors.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppTokens.space24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < 3; i++)
                              _Star(
                                earned: i < summary.stars,
                                progress: _starProgress(masterT, i),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppTokens.space24),
                        _StatLine(
                          label: l10n.scoreLabel,
                          value: displayedScore,
                        ),
                        const SizedBox(height: AppTokens.space8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _CoinFly(progress: scoreT),
                            const SizedBox(width: AppTokens.space4),
                            _StatLine(
                              label: l10n.coinsEarnedLabel,
                              value: displayedCoins,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTokens.space32),
                        FilledButton(
                          onPressed: onContinue,
                          child: Text(l10n.continueButton),
                        ),
                        const SizedBox(height: AppTokens.space24),
                        // TODO(P18): pass a real `onPressed` once the
                        // rewarded ad unit is wired.
                        //
                        // Already routed through `RewardedActionButton`, which
                        // owns Ch10's "disable in place" rule: the button
                        // keeps its exact rectangle whether the player is
                        // online or not, so a finger already travelling
                        // towards it never lands on whatever would have
                        // reflowed into its place.
                        RewardedActionButton(
                          label: l10n.doubleRewardPlaceholder,
                        ),
                        const SizedBox(height: AppTokens.space16),
                        // TODO(P18): MREC (300x250) ad slot.
                        const _MrecPlaceholder(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Star extends StatelessWidget {
  const _Star({required this.earned, required this.progress});

  final bool earned;
  final double progress;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.space4),
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Always-visible slot, so an unearned star reads as "not this
            // time" rather than as a layout gap.
            Icon(Icons.star_rounded, size: _size, color: tokens.colors.outline),
            if (earned)
              Opacity(
                opacity: progress.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: progress,
                  child: Icon(
                    Icons.star_rounded,
                    size: _size,
                    color: tokens.colors.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: AppTypography.uiTextStyle(
            Language.english,
            UiRole.body,
            color: tokens.colors.onSurfaceMuted,
          ),
        ),
        const SizedBox(width: AppTokens.space8),
        Text(
          '$value',
          style: AppTypography.uiTextStyle(
            Language.english,
            UiRole.heading,
            color: tokens.colors.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Ch03's "coin fly-to-counter", scoped to what actually exists on screen:
/// there is still no persistent coin-balance HUD (P15/P16), so this flies a
/// coin glyph directly INTO the card's own coins stat line rather than across
/// widgets this prompt has no business inventing. Driven by the same
/// `scoreT` the coins figure itself rolls up on, so the coin visibly arrives
/// as the number lands.
class _CoinFly extends StatelessWidget {
  const _CoinFly({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final t = Motion.settle.transform(progress.clamp(0.0, 1.0));

    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (1 - t) * -12),
        child: Icon(
          Icons.monetization_on_rounded,
          size: 20,
          color: tokens.colors.primary,
        ),
      ),
    );
  }
}

@immutable
final class _ConfettiPiece {
  const _ConfettiPiece({
    required this.startX,
    required this.delay,
    required this.color,
    required this.rotationSpeed,
    required this.size,
    required this.sway,
  });

  /// 0–1 fraction of the card's width.
  final double startX;

  /// 0–0.35 fraction of `masterT` before this piece is released, so the
  /// burst staggers rather than every piece falling in lockstep.
  final double delay;

  final Color color;

  /// Radians of rotation per full (post-release) `masterT` unit.
  final double rotationSpeed;

  final double size;

  /// Horizontal drift amplitude, in logical pixels, as the piece falls.
  final double sway;
}

List<_ConfettiPiece> _generateConfetti({
  required int seed,
  required List<Color> colors,
}) {
  final random = Random(seed);
  return [
    for (var i = 0; i < LevelCompleteCard._confettiCount; i++)
      _ConfettiPiece(
        startX: random.nextDouble(),
        delay: random.nextDouble() * 0.35,
        color: colors[i % colors.length],
        rotationSpeed: (random.nextDouble() * 2 - 1) * 6,
        size: 5 + random.nextDouble() * 4,
        sway: 10 + random.nextDouble() * 18,
      ),
  ];
}

/// Draws every confetti piece as a pure function of `masterT` — no ticker of
/// its own, unlike `ParticleLayer`. `LevelCompleteCard` already redraws
/// continuously off the ONE `TweenAnimationBuilder` driving everything else
/// on this card, so riding that timeline is simpler than spinning up a
/// second animation system for a screen that only ever plays once.
final class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.masterT, required this.pieces});

  final double masterT;
  final List<_ConfettiPiece> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    for (final piece in pieces) {
      final local = ((masterT - piece.delay) / (1 - piece.delay)).clamp(
        0.0,
        1.0,
      );
      if (local <= 0) continue;

      final fallT = Motion.settle.transform(local);
      final dx = piece.startX * size.width + sin(local * 2 * pi) * piece.sway;
      final dy = fallT * size.height;
      // Full opacity for most of the fall, fading over the last 20% so a
      // piece disappears rather than visibly stopping at the bottom edge.
      final opacity = local < 0.8 ? 1.0 : (1 - (local - 0.8) / 0.2);

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(local * piece.rotationSpeed * pi);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: piece.size,
          height: piece.size * 0.55,
        ),
        Paint()..color = piece.color.withValues(alpha: opacity * 0.85),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.masterT != masterT || !identical(old.pieces, pieces);
}

class _MrecPlaceholder extends StatelessWidget {
  const _MrecPlaceholder();

  /// IAB Medium Rectangle. Reserved at its real size so P18 only has to swap
  /// in the ad widget, never re-layout the card around it.
  static const double _width = 300;
  static const double _height = 250;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = AppLocalizations.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _width),
      child: AspectRatio(
        aspectRatio: _width / _height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.colors.surfaceElevated,
            borderRadius: AppTokens.borderRadius8,
            border: Border.all(color: tokens.colors.outlineSoft),
          ),
          child: Center(
            child: Text(
              l10n.adPlaceholderLabel,
              style: AppTypography.uiTextStyle(
                Language.english,
                UiRole.caption,
                color: tokens.colors.onSurfaceFaint,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
