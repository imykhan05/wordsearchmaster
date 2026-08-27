import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/language/selected_language.dart';
import '../../app/theme/theme.dart';
import '../../data/content/content_repository.dart';
import '../../domain/models/word_entry.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/flavor_badge.dart';

/// FTUE entry point (Ch02): splash lands here directly — no login, no
/// permission dialog, no ad. Three large cards, each rendered in its own
/// script, because the player choosing cannot yet read the others — each
/// card also shows three of that language's own words, from the SAME content
/// pack the grid itself draws from (P10), rather than a second, hand-curated
/// list this screen would own.
///
/// Picking a card goes STRAIGHT into level 1 (`GameRoute('1')`), never
/// `HomeRoute`: Ch02 is explicit — "Level 1 auto-loads. No 'Play' tap
/// required." A returning player who lands back here (there is no other
/// route into `/language` today) gets the same fast path; nothing about
/// re-entering level 1 loses their saved progress, since `level_progress` —
/// not routing — is what tracks completion (P08).
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final selected = ref.watch(selectedLanguageProvider);
    // `.value`, not `.when`: content is a local asset load, not a network
    // call, but this is still the FTUE's very first frame, and a card must
    // render (endonym only) even in the split second before it resolves
    // rather than blocking on a spinner (CLAUDE.md → never block gameplay on
    // a network call — the same caution applies here a fortiori).
    final content = ref.watch(contentRepositoryProvider).value;

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
                    sampleWords: content?.sampleWords(language) ?? const [],
                    onTap: () {
                      ref
                          .read(selectedLanguageProvider.notifier)
                          .select(language);
                      context.go(const GameRoute('1').location);
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
    required this.sampleWords,
    required this.onTap,
  });

  final Language language;
  final bool isSelected;
  final List<WordEntry> sampleWords;
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  language.endonym,
                  style: AppTypography.uiTextStyle(
                    language,
                    UiRole.display,
                    color: tokens.colors.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (sampleWords.isNotEmpty) ...[
                  const SizedBox(height: AppTokens.space8),
                  Text(
                    sampleWords.map((entry) => entry.display).join('  ·  '),
                    style: AppTypography.uiTextStyle(
                      language,
                      UiRole.caption,
                      color: tokens.colors.onSurfaceMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
