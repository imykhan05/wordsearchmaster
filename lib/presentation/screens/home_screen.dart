import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/theme/theme.dart';
import '../../domain/progression/streak.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../../services/audio/audio_service.dart';
import '../../services/haptics/haptics_service.dart';
import '../meta/journey_providers.dart';
import '../meta/meta_tiles.dart';

/// Home (Ch02): the streak counter is the most prominent thing on it, the
/// coin balance sits beside it, and one button drops the player back into the
/// journey exactly where they left off.
///
/// Everything here reads through the P11 providers rather than a repository
/// directly, so the screen renders and decides nothing — the same discipline
/// the journey map keeps.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navHome)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTokens.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _StreakBanner(),
              const SizedBox(height: AppTokens.space16),
              const CoinBalanceTile(),
              const SizedBox(height: AppTokens.space32),
              FilledButton(
                onPressed: () {
                  ref.read(audioServiceProvider).playButtonTap();
                  ref.read(hapticsServiceProvider).buttonTap();
                  context.go(const JourneyRoute().location);
                },
                child: Text(l10n.playButton),
              ),
              const SizedBox(height: AppTokens.space12),
              OutlinedButton(
                onPressed: () {
                  ref.read(audioServiceProvider).playButtonTap();
                  ref.read(hapticsServiceProvider).buttonTap();
                  context.go(const DailyRoute().location);
                },
                child: Text(l10n.navDaily),
              ),
              const SizedBox(height: AppTokens.space12),
              TextButton(
                onPressed: () => context.go(const ProfileRoute().location),
                child: Text(l10n.collectionsTitle),
              ),
              const SizedBox(height: AppTokens.space24),
              Text(
                l10n.appTitle,
                textAlign: TextAlign.center,
                style: AppTypography.uiTextStyle(
                  Language.english,
                  UiRole.caption,
                  color: tokens.colors.onSurfaceFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Ch02 streak counter, and the one place a spent freeze is surfaced.
///
/// A freeze firing is the only streak outcome a player could otherwise
/// mistake for a bug ("I missed Tuesday and my streak is still 12"), so the
/// banner says so explicitly when `StreakEvent.frozen` comes back from the
/// settle — see `StreakRules`' library header.
class _StreakBanner extends ConsumerWidget {
  const _StreakBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final streakAsync = ref.watch(currentStreakProvider);

    final transition = streakAsync.value;
    final state = transition?.state ?? StreakState.empty;

    return MetaCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                size: 40,
                color: state.current > 0
                    ? tokens.colors.primary
                    : tokens.colors.onSurfaceFaint,
              ),
              const SizedBox(width: AppTokens.space8),
              Text(
                '${state.current}',
                style: AppTypography.uiTextStyle(
                  Language.english,
                  UiRole.display,
                  color: tokens.colors.onSurface,
                ),
              ),
            ],
          ),
          Text(
            l10n.streakLabel,
            style: AppTypography.uiTextStyle(
              Language.english,
              UiRole.caption,
              color: tokens.colors.onSurfaceMuted,
            ),
          ),
          if (state.freezes > 0) ...[
            const SizedBox(height: AppTokens.space8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.ac_unit_rounded,
                  size: 16,
                  color: tokens.colors.info,
                ),
                const SizedBox(width: AppTokens.space4),
                Text(
                  l10n.streakFreezesLabel(state.freezes),
                  style: AppTypography.uiTextStyle(
                    Language.english,
                    UiRole.caption,
                    color: tokens.colors.info,
                  ),
                ),
              ],
            ),
          ],
          if (transition?.event == StreakEvent.frozen) ...[
            const SizedBox(height: AppTokens.space8),
            Text(
              l10n.streakFrozenMessage,
              textAlign: TextAlign.center,
              style: AppTypography.uiTextStyle(
                Language.english,
                UiRole.caption,
                color: tokens.colors.info,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
