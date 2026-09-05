import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/theme/theme.dart';
import '../../application/leaderboard_controller.dart';
import '../../data/remote/name_report_api.dart';
import '../../data/repositories/leaderboard_cache.dart';
import '../../domain/leaderboard/leaderboard_keys.dart' as leaderboard_keys;
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth/auth_service.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/time/trusted_clock.dart';
import '../meta/friends_tab.dart';
import '../meta/meta_tiles.dart';
import '../widgets/flavor_badge.dart';
import '../widgets/system_back_handler.dart';
import '../widgets/sync_status.dart';

/// The leaderboard: Global / Urdu / Hindi / English / Weekly / Daily / Friends
/// (P17), rebuilt on top of P16's cache-first foundation.
///
/// ---------------------------------------------------------------------------
/// WHY THIS IS NOT A `TabBarView`
///
/// "Real-time snapshots ONLY on the currently visible tab, detached on
/// navigate away" is one of P17's three acceptance criteria, and
/// `TabBarView`'s `PageView` keeps neighbouring pages BUILT for swipe
/// smoothness — exactly the opposite of what a per-tab Firestore listener
/// needs. So there is no `TabController`/`TabBarView` anywhere here: [_tab]
/// is plain local state, and the body is a `switch` that constructs ONLY the
/// selected tab's subtree. Switching tabs unmounts the old one outright,
/// which is what lets `leaderboardTopProvider` (an `autoDispose` family — see
/// its own file header) actually tear its stream down rather than merely
/// stop being the active page.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

enum _BoardTab { global, ur, hi, en, weekly, daily, friends }

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  _BoardTab _tab = _BoardTab.global;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Reached with `.go()`, so there is nothing to pop: both the arrow and
    // the Android system back have to navigate explicitly, or the app closes.
    void goHome() => context.go(const HomeRoute().location);

    return SystemBackHandler(
      onBack: goHome,
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: goHome),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: FlavorBadge(),
                ),
                const SizedBox(height: AppTokens.space16),
                _TabStrip(
                  selected: _tab,
                  onSelect: (tab) => setState(() => _tab = tab),
                ),
                const SizedBox(height: AppTokens.space16),
                Expanded(
                  // KeyedSubtree per tab: a new key forces a fresh element (and a
                  // fresh provider watch) rather than Flutter reusing the old
                  // `_BoardBody`'s state across a board-id change — belt and
                  // braces alongside the `switch` itself never re-showing the
                  // previous tab's tree.
                  child: switch (_tab) {
                    _BoardTab.friends => const FriendsTab(
                      key: ValueKey(_BoardTab.friends),
                    ),
                    final tab => _BoardBody(tab: tab, key: ValueKey(tab)),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.selected, required this.onSelect});

  final _BoardTab selected;
  final ValueChanged<_BoardTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Language endonyms, not localized labels — CLAUDE.md's own rule for
    // `Language.endonym`: a player who reads only Urdu has to find the Urdu
    // tab by its own script, not by whatever language the UI happens to be in.
    final labels = <_BoardTab, String>{
      _BoardTab.global: l10n.leaderboardTabGlobal,
      _BoardTab.ur: Language.urdu.endonym,
      _BoardTab.hi: Language.hindi.endonym,
      _BoardTab.en: Language.english.endonym,
      _BoardTab.weekly: l10n.leaderboardTabWeekly,
      _BoardTab.daily: l10n.leaderboardTabDaily,
      _BoardTab.friends: l10n.leaderboardTabFriends,
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in _BoardTab.values)
            Padding(
              padding: const EdgeInsets.only(right: AppTokens.space8),
              child: ChoiceChip(
                label: Text(labels[tab]!),
                selected: tab == selected,
                onSelected: (_) => onSelect(tab),
              ),
            ),
        ],
      ),
    );
  }
}

/// Resolves [tab] to a board id — synchronous for the four evergreen boards,
/// waiting on [currentDayProvider] for Weekly/Daily, whose ids are date-keyed
/// (`domain/leaderboard/leaderboard_keys.dart`, a byte-for-byte port of the
/// server's own `leaderboardKeys.ts`).
class _BoardBody extends ConsumerWidget {
  const _BoardBody({required this.tab, super.key});

  final _BoardTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tab == _BoardTab.weekly || tab == _BoardTab.daily) {
      final day = ref.watch(currentDayProvider);
      return switch (day) {
        AsyncData(:final value) => _Board(
          board: tab == _BoardTab.weekly
              ? leaderboard_keys.weeklyBoardId(value.utcMidnight)
              : leaderboard_keys.dailyBoardId(value),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
    }

    final board = switch (tab) {
      _BoardTab.global => leaderboard_keys.globalBoard,
      _BoardTab.ur => leaderboard_keys.languageBoardId(Language.urdu.code),
      _BoardTab.hi => leaderboard_keys.languageBoardId(Language.hindi.code),
      _BoardTab.en => leaderboard_keys.languageBoardId(Language.english.code),
      _BoardTab.weekly ||
      _BoardTab.daily ||
      _BoardTab.friends => throw StateError('unreachable'),
    };
    return _Board(board: board);
  }
}

class _Board extends ConsumerWidget {
  const _Board({required this.board});

  final String board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final live = ref.watch(leaderboardTopProvider(board));
    final cached = ref.watch(cachedLeaderboardProvider(board));
    final online = ref.watch(isOnlineProvider).value ?? true;
    final uid = ref.watch(currentAccountProvider).value?.uid;
    final ownEntry = ref.watch(ownLeaderboardEntryProvider(board));

    final entries = live.value ?? cached.value?.entries ?? const [];
    final fetchedAtMillis = live.hasValue
        ? DateTime.now().millisecondsSinceEpoch
        : cached.value?.fetchedAtMillis;

    if (entries.isEmpty) {
      final stillLoading = live.isLoading && !live.hasValue && !cached.hasValue;
      return stillLoading
          ? const Center(child: CircularProgressIndicator())
          : const _EmptyBoard();
    }

    final showsSelf = uid != null && entries.any((e) => e.uid == uid);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fetchedAtMillis != null) ...[
          LastUpdatedLabel(timestampMillis: fetchedAtMillis),
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
        ],
        Expanded(
          child: ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppTokens.space8),
            itemBuilder: (context, index) => _EntryRow(
              rank: index + 1,
              entry: entries[index],
              currentUid: uid,
            ),
          ),
        ),
        // PINNED ROW: only when the signed-in player is outside [entries] —
        // P17's own acceptance wording. `ownEntry` is a ONE-SHOT read
        // (`LeaderboardApi.fetchOwnEntry`'s header explains why a rank is
        // never live), so this row can lag the live list by up to
        // `recomputeLeaderboardRanks`'s own 15-minute cadence; that is the
        // documented trade in `SECURITY.md`'s AR-10, not a bug here.
        if (uid != null && !showsSelf) ...[
          const SizedBox(height: AppTokens.space8),
          _PinnedSelfRow(entry: ownEntry.value),
        ],
      ],
    );
  }
}

class _EntryRow extends ConsumerWidget {
  const _EntryRow({
    required this.rank,
    required this.entry,
    required this.currentUid,
  });

  final int rank;
  final LeaderboardEntry entry;

  /// Null with no signed-in account. Hides the report action on the row's
  /// own entry — reporting yourself is refused server-side anyway
  /// (`firestore.rules`), but there is no reason to show the button at all.
  final String? currentUid;

  /// A confirm step before a report that has a real, if delayed and
  /// threshold-gated, consequence for someone else's account (AR-4 / T12) —
  /// worth guarding against an accidental tap the way none of this screen's
  /// other rows need to.
  Future<void> _confirmAndReport(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.reportNameConfirmTitle),
        content: Text(l10n.reportNameConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.reportNameCancelAction),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.reportNameConfirmAction),
          ),
        ],
      ),
    );
    final reporterUid = currentUid;
    if (confirmed != true || reporterUid == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final success = await ref
        .read(nameReportApiProvider)
        .reportDisplayName(reporterUid: reporterUid, reportedUid: entry.uid);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? l10n.reportNameSubmittedMessage
              : l10n.reportNameFailedMessage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final name = entry.displayName ?? entry.uid;
    final canReport = currentUid != null && currentUid != entry.uid;

    return MetaCard(
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: AppTypography.uiTextStyle(
                Language.english,
                UiRole.body,
                color: tokens.colors.onSurfaceMuted,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.space8),
          CircleAvatar(
            radius: 16,
            backgroundColor: tokens.colors.primaryDim,
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: AppTypography.uiTextStyle(
                Language.english,
                UiRole.caption,
                color: tokens.colors.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.space16),
          Expanded(
            child: Text(
              name,
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
          if (canReport)
            IconButton(
              tooltip: l10n.reportNameAction,
              iconSize: 18,
              onPressed: () => unawaited(_confirmAndReport(context, ref, l10n)),
              icon: Icon(
                Icons.flag_outlined,
                color: tokens.colors.onSurfaceFaint,
              ),
            ),
        ],
      ),
    );
  }
}

class _PinnedSelfRow extends StatelessWidget {
  const _PinnedSelfRow({required this.entry});

  final LeaderboardEntry? entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final rank = entry?.rank;

    return MetaCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              rank != null
                  ? l10n.leaderboardYourRank(rank)
                  : l10n.leaderboardRankUnknown,
              style: AppTypography.uiTextStyle(
                Language.english,
                UiRole.body,
                color: tokens.colors.primary,
              ),
            ),
          ),
          if (entry != null)
            Text(
              '${entry!.score}',
              style: AppTypography.uiTextStyle(
                Language.english,
                UiRole.body,
                color: tokens.colors.primary,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);

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
