import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/theme.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import 'journey_providers.dart';

/// The elevated panel every meta screen frames a block of content in.
///
/// One definition rather than a `Container` per screen, so the home, daily and
/// collections screens cannot drift into three slightly different card
/// treatments — and so a change to elevation lands everywhere at once.
class MetaCard extends StatelessWidget {
  const MetaCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final elevation = tokens.elevation1;

    return Container(
      padding: const EdgeInsets.all(AppTokens.space16),
      decoration: BoxDecoration(
        color: elevation.surface,
        borderRadius: AppTokens.borderRadius16,
        border: Border.all(color: tokens.colors.outlineSoft),
        boxShadow: elevation.shadows,
      ),
      child: child,
    );
  }
}

/// The player's coin balance, live off the verified ledger (P08).
class CoinBalanceTile extends ConsumerWidget {
  const CoinBalanceTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    // A balance that has not resolved yet shows 0 rather than a spinner: it
    // settles within a frame off a local database, and a spinner where a
    // number belongs is more disruptive than a number that ticks up.
    final balance = ref.watch(coinBalanceProvider).value ?? 0;

    return MetaCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.monetization_on_rounded,
            size: 24,
            color: tokens.colors.primary,
          ),
          const SizedBox(width: AppTokens.space8),
          Text(
            '$balance',
            style: AppTypography.uiTextStyle(
              Language.english,
              UiRole.title,
              color: tokens.colors.onSurface,
            ),
          ),
          const SizedBox(width: AppTokens.space8),
          Text(
            l10n.coinsLabel,
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
