import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/theme.dart';
import '../../data/repositories/leaderboard_cache.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../meta/meta_tiles.dart';
import '../widgets/flavor_badge.dart';
import '../widgets/sync_status.dart';

/// The leaderboard, rendered from the LAST SAVED COPY (Ch10 / P16).
///
/// ---------------------------------------------------------------------------
/// CACHE FIRST, NOT NETWORK FIRST
///
/// Ch10's rule for this screen is cached data plus a "last updated" relative
/// timestamp when offline — never a spinner that never resolves, never an
/// error, and never a "no internet" dialog. So the cache is what this widget
/// reads, always, in both states: online simply means a fresher copy will be
/// written under it, not that the screen switches to a different data source.
///
/// One data path rather than two is also what makes the offline case correct
/// by construction. A screen that read the network when online and the cache
/// when offline would have an untested branch that only fires on a bad
/// connection — which is the connection this game's audience mostly has.
///
/// ---------------------------------------------------------------------------
/// P17 OWNS THE FETCH
///
/// Nothing here refreshes the cache. `LeaderboardCache` is the store and P17's
/// prompt owns filling it from Firestore, so on this build the screen shows
/// whatever the cache holds — empty until then. That split is deliberate:
/// P16's job is that the OFFLINE path exists, renders honestly, and cannot
/// interrupt the player.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cached = ref.watch(cachedGlobalLeaderboardProvider);
    final online = ref.watch(isOnlineProvider).value ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navLeaderboard),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: AppTokens.space16),
            child: Center(child: SyncStatusIndicator()),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.space24),
          // The badge travels with the screen, not with `StubScreen` — P01's
          // rule is that dev and stg are unmistakable on EVERY screen, and a
          // real screen replacing a stub must not quietly drop it.
          // `cached` is an AsyncValue over a LOCAL read, so its loading state
          // lasts a frame or two — never the open-ended wait a network read
          // would produce. An error degrades to the empty copy rather than to
          // an error screen: a board nobody could read is the same experience
          // as a board with nothing in it, and only one of those needs a
          // player to understand it.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: FlavorBadge(),
              ),
              const SizedBox(height: AppTokens.space16),
              Expanded(
                child: switch (cached) {
                  AsyncData(:final value)
                      when value != null && value.entries.isNotEmpty =>
                    _Board(snapshot: value, online: online),
                  _ => const _EmptyBoard(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.snapshot, required this.online});

  final CachedLeaderboard snapshot;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The staleness stamp is shown in BOTH states, not only offline. A
        // label that appeared when the connection dropped would itself be a
        // "you are offline" notification, which is the thing Ch10 forbids —
        // and a player online with a four-hour-old copy deserves the same
        // information as one who is offline with it.
        LastUpdatedLabel(timestampMillis: snapshot.fetchedAtMillis),
        if (!online) ...[
          const SizedBox(height: AppTokens.space4),
          Text(
            l10n.leaderboardOfflineNote,
            style: AppTypography.uiTextStyle(
              Language.english,
              UiRole.caption,
              color: tokens.colors.onSurfaceFaint,
            ),
          ),
        ],
        const SizedBox(height: AppTokens.space16),
        Expanded(
          child: ListView.separated(
            itemCount: snapshot.entries.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppTokens.space8),
            itemBuilder: (context, index) {
              final entry = snapshot.entries[index];
              return MetaCard(
                child: Row(
                  children: [
                    Text(
                      '${index + 1}',
                      style: AppTypography.uiTextStyle(
                        Language.english,
                        UiRole.body,
                        color: tokens.colors.onSurfaceMuted,
                      ),
                    ),
                    const SizedBox(width: AppTokens.space16),
                    Expanded(
                      child: Text(
                        entry.displayName ?? entry.uid,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.uiTextStyle(
                          Language.english,
                          UiRole.body,
                          color: tokens.colors.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '${entry.score}',
                      style: AppTypography.uiTextStyle(
                        Language.english,
                        UiRole.body,
                        color: tokens.colors.onSurface,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);

    // Plain text, centred. Not an error, not a retry button: there is nothing
    // for the player to retry, and offering one would imply the empty board is
    // their problem to solve.
    return Center(
      child: Text(
        l10n.leaderboardEmpty,
        textAlign: TextAlign.center,
        style: AppTypography.uiTextStyle(
          Language.english,
          UiRole.body,
          color: tokens.colors.onSurfaceMuted,
        ),
      ),
    );
  }
}
