import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/language/selected_language.dart';
import '../../app/theme/theme.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/flavor_badge.dart';

/// FTUE entry point (Ch02): splash lands here directly — no login, no
/// permission dialog, no ad. Three large cards, each rendered in its own
/// script, because the player choosing cannot yet read the others.
///
/// P12 builds the full version (sample words per card, auto-advance into
/// level 1). This is the minimum that makes language selection real, so the
/// app-wide [Directionality] can actually be exercised.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final selected = ref.watch(selectedLanguageProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.space24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FlavorBadge(),
                const SizedBox(height: AppTokens.space24),
                Text(
                  l10n.chooseLanguage,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTokens.space32),
                for (final language in Language.values) ...[
                  _LanguageCard(
                    language: language,
                    isSelected: language == selected,
                    onTap: () {
                      ref
                          .read(selectedLanguageProvider.notifier)
                          .select(language);
                      context.go(const HomeRoute().location);
                    },
                  ),
                  const SizedBox(height: AppTokens.space12),
                ],
                const SizedBox(height: AppTokens.space8),
                Text(
                  '${selected.code} · ${selected.isRtl ? 'RTL' : 'LTR'}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: AppTokens.space8),
                Container(height: 1, color: tokens.colors.outlineSoft),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.language,
    required this.isSelected,
    required this.onTap,
  });

  final Language language;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Semantics(
      button: true,
      selected: isSelected,
      label: language.endonym,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTokens.borderRadius16,
        child: Container(
          width: 260,
          constraints: const BoxConstraints(minHeight: 72),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space24,
            vertical: AppTokens.space16,
          ),
          decoration: BoxDecoration(
            color: tokens.elevation1.surface,
            borderRadius: AppTokens.borderRadius16,
            border: Border.all(
              color: isSelected ? tokens.colors.primary : tokens.colors.outline,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: tokens.elevation1.shadows,
          ),
          // Each card renders in ITS OWN script and direction, not the
          // currently-selected one — the whole point is that a player who
          // reads only Urdu can find the Urdu card.
          child: Directionality(
            textDirection: language.isRtl
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: Text(
              language.endonym,
              style: AppTypography.uiTextStyle(
                language,
                UiRole.display,
                color: tokens.colors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
