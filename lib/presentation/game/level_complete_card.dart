import 'package:flutter/material.dart';

import '../../app/theme/theme.dart';
import '../../application/game_controller.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';

/// Full-screen result card shown while `GameState.phase` is
/// `GamePhase.levelComplete`.
///
/// Stateless: the whole staggered reveal (stars, then score, then coins) is
/// one [TweenAnimationBuilder] over a single fixed timeline, each piece
/// computing its own local progress from a slice of it — the same shape
/// P06's docs describe for the found-word choreography, just with three
/// slices instead of one.
///
/// By the time this shows, [GameController] has already generated the NEXT
/// level behind it (Ch02 Zeigarnik) — [onContinue] is only ever a phase
/// flip, never a new load, so there is nothing to wait for here.
class LevelCompleteCard extends StatelessWidget {
  const LevelCompleteCard({
    required this.summary,
    required this.onContinue,
    super.key,
  });

  final LevelCompletionSummary summary;
  final VoidCallback onContinue;

  static const int _starStaggerMs = 140;
  static const int _starPopMs = 140;
  static const int _starsDoneMs = _starStaggerMs * 2 + _starPopMs;
  static const int _scoreRollMs = 400;
  static const int _totalMs = _starsDoneMs + _scoreRollMs;
  static const Duration _totalDuration = Duration(milliseconds: _totalMs);

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

    return ColoredBox(
      color: tokens.colors.background.withValues(alpha: 0.96),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTokens.space24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: Motion.reduced(context, _totalDuration),
              builder: (context, masterT, child) {
                final scoreT = _scoreProgress(masterT);
                final displayedScore = (summary.score * scoreT).round();
                final displayedCoins = (summary.coinsEarned * scoreT).round();

                return Column(
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
                    _StatLine(label: l10n.scoreLabel, value: displayedScore),
                    const SizedBox(height: AppTokens.space8),
                    _StatLine(
                      label: l10n.coinsEarnedLabel,
                      value: displayedCoins,
                    ),
                    const SizedBox(height: AppTokens.space32),
                    FilledButton(
                      onPressed: onContinue,
                      child: Text(l10n.continueButton),
                    ),
                    const SizedBox(height: AppTokens.space24),
                    // TODO(P18): rewarded-ad double-reward action. Disabled
                    // rather than hidden, so the layout it will occupy is
                    // already correct.
                    OutlinedButton(
                      onPressed: null,
                      child: Text(l10n.doubleRewardPlaceholder),
                    ),
                    const SizedBox(height: AppTokens.space16),
                    // TODO(P18): MREC (300x250) ad slot.
                    const _MrecPlaceholder(),
                  ],
                );
              },
            ),
          ),
        ),
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
