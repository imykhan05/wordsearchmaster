import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/theme.dart';
import '../../domain/progression/collections.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_card.dart';
import '../meta/journey_providers.dart';
import '../meta/meta_tiles.dart';

/// Profile, which for P11 is the COLLECTIONS grid (Ch02): one slot per word
/// category in the selected language, filled when every level of that category
/// is finished.
///
/// The rest of the profile (display name, avatar, cloud account) belongs to
/// P13's auth work and P17's real profile screen — this prompt owns the
/// badges and puts them somewhere reachable rather than inventing a screen it
/// would then have to take back.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final collectionsAsync = ref.watch(collectionsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navProfile)),
      body: SafeArea(
        child: collectionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (state) => _CollectionsGrid(state: state),
        ),
      ),
    );
  }
}

class _CollectionsGrid extends StatelessWidget {
  const _CollectionsGrid({required this.state});

  final CollectionsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final earned = state.badges.where((badge) => badge.isEarned).length;

    return CustomScrollView(
      slivers: [
        // Ch02: Google Sign-In is offered after level 8 (the home banner) AND
        // from the profile screen — this is that second entry point, and the
        // only place a linked player can sign out again.
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppTokens.space24,
              AppTokens.space24,
              AppTokens.space24,
              0,
            ),
            child: AccountCard(),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.space24),
            child: MetaCard(
              child: Column(
                children: [
                  Text(
                    l10n.collectionsTitle,
                    style: AppTypography.uiTextStyle(
                      Language.english,
                      UiRole.title,
                      color: tokens.colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppTokens.space4),
                  Text(
                    l10n.collectionsProgress(earned, state.badges.length),
                    style: AppTypography.uiTextStyle(
                      Language.english,
                      UiRole.caption,
                      color: tokens.colors.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.space24),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              mainAxisSpacing: AppTokens.space12,
              crossAxisSpacing: AppTokens.space12,
              childAspectRatio: 0.85,
            ),
            itemCount: state.badges.length,
            itemBuilder: (context, index) =>
                _BadgeSlot(badge: state.badges[index]),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppTokens.space48)),
      ],
    );
  }
}

/// One collection slot: filled when earned, an outline with a progress ring
/// when not (Ch02's "filled/empty slots", plus the ring — see
/// `CategoryBadge.progress` for why a purely binary grid would sit empty for
/// hours).
class _BadgeSlot extends StatelessWidget {
  const _BadgeSlot({required this.badge});

  final CategoryBadge badge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final earned = badge.isEarned;

    return Container(
      padding: const EdgeInsets.all(AppTokens.space8),
      decoration: BoxDecoration(
        color: earned
            ? tokens.colors.primary.withValues(alpha: 0.18)
            : tokens.colors.surface,
        borderRadius: AppTokens.borderRadius16,
        border: Border.all(
          color: earned ? tokens.colors.primary : tokens.colors.outline,
          width: earned ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!earned)
                  CircularProgressIndicator(
                    value: badge.progress,
                    strokeWidth: 3,
                    backgroundColor: tokens.colors.outlineSoft,
                    color: tokens.colors.primaryDim,
                  ),
                Icon(
                  earned
                      ? Icons.workspace_premium_rounded
                      : Icons.lock_outline_rounded,
                  size: earned ? 32 : 20,
                  color: earned
                      ? tokens.colors.primary
                      : tokens.colors.onSurfaceFaint,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.space4),
          Text(
            // The raw category key ("animals"). NOT localized, deliberately
            // and temporarily: the twelve categories are content-side labels
            // (P10 writes them into every `WordEntry`), so localizing them
            // means twelve more ARB entries per language reviewed by the same
            // native speaker who still has to review the word packs
            // themselves. Flagged with them rather than machine-drafted here.
            // TODO(P17/P21): localized category names, native-reviewed.
            badge.category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.uiTextStyle(
              Language.english,
              UiRole.caption,
              color: tokens.colors.onSurface,
            ),
          ),
          Text(
            l10n.collectionsProgress(badge.levelsCompleted, badge.levelsTotal),
            style: AppTypography.uiTextStyle(
              Language.english,
              UiRole.caption,
              color: tokens.colors.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}
