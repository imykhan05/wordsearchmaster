import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/theme/theme.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../../services/audio/audio_service.dart';
import '../../services/haptics/haptics_service.dart';
import '../../services/time/trusted_clock.dart';
import '../meta/journey_providers.dart';
import '../meta/meta_tiles.dart';

/// The Daily Challenge's pre-game screen (Ch12): today's date, whether the one
/// attempt has been used, and the button in.
///
/// NOTHING HERE TOUCHES THE NETWORK, and that is the point. The puzzle is
/// derived from the UTC date on-device (P10's `getDailySeed` →
/// `DailyPuzzle`), the one-attempt gate reads the local `daily_results` table,
/// and the leaderboard submission leaves through the outbox whenever a
/// connection next exists. So this screen behaves identically in airplane
/// mode — there is no "offline" variant of it, because there is no online
/// path to fall back from.
///
/// Per CLAUDE.md → Never do, there is no "no internet" dialog anywhere in
/// this flow.
class DailyScreen extends ConsumerWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final resultAsync = ref.watch(todaysDailyResultProvider);
    final dayAsync = ref.watch(currentDayProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navDaily)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.space24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MetaCard(
                    child: Column(
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 40,
                          color: tokens.colors.primary,
                        ),
                        const SizedBox(height: AppTokens.space8),
                        Text(
                          // The UTC day key itself, not a localized date:
                          // this IS the puzzle's identity (`daily_results` is
                          // keyed by it), and every player worldwide sees the
                          // same string for the same puzzle.
                          '${dayAsync.value ?? ''}',
                          style: AppTypography.uiTextStyle(
                            Language.english,
                            UiRole.title,
                            color: tokens.colors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.space24),
                  resultAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Center(child: Text('$error')),
                    data: (result) => result != null
                        ? _AlreadyPlayed(
                            stars: result.stars,
                            score: result.score,
                          )
                        : _PlayToday(
                            onPlay: () {
                              ref.read(audioServiceProvider).playButtonTap();
                              ref.read(hapticsServiceProvider).buttonTap();
                              context.go(const DailyGameRoute().location);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayToday extends StatelessWidget {
  const _PlayToday({required this.onPlay});

  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(onPressed: onPlay, child: Text(l10n.dailyPlayButton)),
        const SizedBox(height: AppTokens.space8),
        Text(
          l10n.dailyOneAttempt,
          textAlign: TextAlign.center,
          style: AppTypography.uiTextStyle(
            Language.english,
            UiRole.caption,
            color: tokens.colors.onSurfaceMuted,
          ),
        ),
      ],
    );
  }
}

class _AlreadyPlayed extends StatelessWidget {
  const _AlreadyPlayed({required this.stars, required this.score});

  final int stars;
  final int score;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);

    return MetaCard(
      child: Column(
        children: [
          Text(
            l10n.dailyAlreadyPlayed,
            textAlign: TextAlign.center,
            style: AppTypography.uiTextStyle(
              Language.english,
              UiRole.body,
              color: tokens.colors.onSurface,
            ),
          ),
          const SizedBox(height: AppTokens.space12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Icon(
                  Icons.star_rounded,
                  size: 32,
                  color: i < stars
                      ? tokens.colors.primary
                      : tokens.colors.outline,
                ),
            ],
          ),
          const SizedBox(height: AppTokens.space8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                l10n.scoreLabel,
                style: AppTypography.uiTextStyle(
                  Language.english,
                  UiRole.caption,
                  color: tokens.colors.onSurfaceMuted,
                ),
              ),
              const SizedBox(width: AppTokens.space8),
              Text(
                '$score',
                style: AppTypography.uiTextStyle(
                  Language.english,
                  UiRole.heading,
                  color: tokens.colors.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
