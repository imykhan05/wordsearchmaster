import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/theme/theme.dart';
import '../../domain/progression/coin_economy.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';

/// The chest-opening celebration (Ch02) — shown every
/// `chest_every_n_levels`-th level.
///
/// ONE `TweenAnimationBuilder`, ONE PAINTER, no ticker of its own. Exactly the
/// shape `LevelCompleteCard` already uses (P09): a single master timeline
/// drives the lid, the burst and the coin count, each computing its own local
/// progress from a slice of it. A screen that plays once every five levels
/// does not need a second animation system, and on the 2GB-RAM target the
/// cheapest celebration that still reads as one is the right one.
///
/// Reduce-motion (Ch03) collapses the whole thing: the burst is never
/// generated (skipped outright, not shortened), and the timeline resolves to
/// zero so the chest is simply open with its number already showing.
class ChestOpenCard extends StatelessWidget {
  const ChestOpenCard({
    required this.reward,
    required this.onDismiss,
    super.key,
  });

  final ChestReward reward;
  final VoidCallback onDismiss;

  /// Slices of the master timeline, in ms. The lid pops first, the burst
  /// fires as it clears, and the coin count rolls up behind both.
  static const int _lidMs = 260;
  static const int _burstMs = 420;
  static const int _countMs = 400;
  static const int _totalMs = _lidMs + _countMs;
  static const Duration _totalDuration = Duration(milliseconds: _totalMs);

  /// Matches `ParticleLayer`'s 8–12 and `LevelCompleteCard`'s 24 — a budget,
  /// not a maximum.
  static const int _sparkCount = 18;

  double _lidProgress(double masterT) =>
      Motion.punch.transform((masterT * _totalMs / _lidMs).clamp(0.0, 1.0));

  double _burstProgress(double masterT) =>
      ((masterT * _totalMs - _lidMs * 0.6) / _burstMs).clamp(0.0, 1.0);

  double _countProgress(double masterT) =>
      ((masterT * _totalMs - _lidMs) / _countMs).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final sparks = MediaQuery.disableAnimationsOf(context)
        ? const <_Spark>[]
        : _generateSparks(
            seed: reward.coins ^ reward.tier.id.hashCode,
            colors: tokens.colors.foundWord,
          );

    return ColoredBox(
      color: tokens.colors.background.withValues(alpha: 0.96),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: Motion.reduced(context, _totalDuration),
        builder: (context, masterT, child) {
          final coins = (reward.coins * _countProgress(masterT)).round();

          return Stack(
            children: [
              if (sparks.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SparkPainter(
                        progress: _burstProgress(masterT),
                        sparks: sparks,
                      ),
                    ),
                  ),
                ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.space24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.chestOpenTitle,
                        style: AppTypography.uiTextStyle(
                          Language.english,
                          UiRole.display,
                          color: tokens.colors.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppTokens.space24),
                      _Chest(lidProgress: _lidProgress(masterT)),
                      const SizedBox(height: AppTokens.space24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.monetization_on_rounded,
                            size: 28,
                            color: tokens.colors.primary,
                          ),
                          const SizedBox(width: AppTokens.space8),
                          Text(
                            '$coins',
                            style: AppTypography.uiTextStyle(
                              Language.english,
                              UiRole.display,
                              color: tokens.colors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.space32),
                      FilledButton(
                        onPressed: onDismiss,
                        child: Text(l10n.continueButton),
                      ),
                    ],
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

/// A chest glyph whose lid tilts open as [lidProgress] runs 0→1.
///
/// Two `Icon`s and a rotation rather than an asset: the art budget belongs to
/// the fonts (Ch04 bundles ~2.7MB of Noto before subsetting), and a chest that
/// ships as zero bytes and still reads as a chest is the right trade for a
/// celebration this size.
class _Chest extends StatelessWidget {
  const _Chest({required this.lidProgress});

  final double lidProgress;

  static const double _size = 96;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final t = lidProgress.clamp(0.0, 1.0);

    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow behind the chest, growing as the lid clears.
          Opacity(
            opacity: t * 0.5,
            child: Container(
              width: _size * (0.5 + t * 0.5),
              height: _size * (0.5 + t * 0.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tokens.colors.primary.withValues(alpha: 0.35),
              ),
            ),
          ),
          Icon(
            Icons.inventory_2_rounded,
            size: _size,
            color: tokens.colors.primaryDim,
          ),
          Transform.translate(
            offset: Offset(0, -t * _size * 0.28),
            child: Transform.rotate(
              angle: -t * 0.5,
              child: Icon(
                Icons.expand_less_rounded,
                size: _size * 0.7,
                color: tokens.colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

@immutable
final class _Spark {
  const _Spark({
    required this.angle,
    required this.distance,
    required this.color,
    required this.size,
  });

  final double angle;
  final double distance;
  final Color color;
  final double size;
}

List<_Spark> _generateSparks({required int seed, required List<Color> colors}) {
  final random = Random(seed);
  return [
    for (var i = 0; i < ChestOpenCard._sparkCount; i++)
      _Spark(
        // Evenly spread around the circle plus jitter, so the burst reads as
        // a burst rather than as a cluster a uniform random draw would give.
        angle:
            (i / ChestOpenCard._sparkCount) * 2 * pi +
            (random.nextDouble() - 0.5) * 0.4,
        distance: 60 + random.nextDouble() * 90,
        color: colors[i % colors.length],
        size: 3 + random.nextDouble() * 4,
      ),
  ];
}

final class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.progress, required this.sparks});

  final double progress;
  final List<_Spark> sparks;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final eased = Motion.settle.transform(progress);
    // Fades over the last 30% so a spark disappears rather than stopping.
    final opacity = progress < 0.7 ? 1.0 : (1 - (progress - 0.7) / 0.3);

    for (final spark in sparks) {
      final travelled = spark.distance * eased;
      final offset =
          center + Offset(cos(spark.angle), sin(spark.angle)) * travelled;
      canvas.drawCircle(
        offset,
        spark.size * (1 - eased * 0.4),
        Paint()..color = spark.color.withValues(alpha: opacity * 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.progress != progress || !identical(old.sparks, sparks);
}
