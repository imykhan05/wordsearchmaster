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
import '../widgets/system_back_handler.dart';
import '../widgets/tap_feedback.dart';

/// FTUE entry point (Ch02): the splash lands a first-time player here —
/// no login, no permission dialog, no ad. Three large cards, each rendered in
/// its own script, because the player choosing cannot yet read the others —
/// each card also shows three of that language's own words, from the SAME
/// content pack the grid itself draws from (P10), rather than a second,
/// hand-curated list this screen would own.
///
/// Picking a card goes to `HomeRoute` — Play/Journey, Daily Challenge and
/// Leaderboard are all one tap from there, per the player's own explicit
/// request for a splash → language-select → Home flow. This is a deliberate
/// departure from the shipped P12 rule ("Level 1 auto-loads, no Play tap
/// required"): a first-time player now sees the hub before the first grid,
/// which costs one extra tap to reach level 1 in exchange for the same
/// Play/Daily/Leaderboard choice a returning player already gets. Nothing
/// about `GameController`, `ProgressionController` or the Zeigarnik swap
/// changed — this is purely which route a card's `onTap` lands on.
///
/// A RETURNING player reaches this same screen a second way (post-P17): the
/// Profile screen's language tile, for a player who wants to switch. Picking
/// a card there also lands on `HomeRoute` — the same destination as FTUE now,
/// which is why `onTap` no longer branches on it. `hasChosenLanguageProvider`
/// still tells the two apart for the ONE thing that still differs — the back
/// arrow, present only for a returning player, since the FTUE has nothing
/// valid to go back to — and is still READ once at build, not watched, for
/// the identical reason this file already documented: watching would flip
/// the arrow on mid-tap. Reached from Profile via `.go()`, which replaces the
/// stack, so this screen needs its own way out when nothing was picked.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final selected = ref.watch(selectedLanguageProvider);
    final returning = ref.read(hasChosenLanguageProvider);
    // `.value`, not `.when`: content is a local asset load, not a network
    // call, but this is still the FTUE's very first frame, and a card must
    // render (endonym only) even in the split second before it resolves
    // rather than blocking on a spinner (CLAUDE.md → never block gameplay on
    // a network call — the same caution applies here a fortiori).
    final content = ref.watch(contentRepositoryProvider).value;

    void goHome() {
      ref.tapFeedback();
      context.go(const HomeRoute().location);
    }

    final body = SafeArea(
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
                    ref.tapFeedback();
                    ref
                        .read(selectedLanguageProvider.notifier)
                        .select(language);
                    // BOTH paths land on Home now — see this file's own
                    // header for why, and why `returning` therefore no
                    // longer branches here even though it still decides the
                    // back arrow below.
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
    );

    if (!returning) return Scaffold(body: body);

    return SystemBackHandler(
      onBack: goHome,
      child: Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: goHome)),
        body: body,
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
