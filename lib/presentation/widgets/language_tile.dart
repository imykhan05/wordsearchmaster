import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/language/selected_language.dart';
import '../../app/theme/theme.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../meta/meta_tiles.dart';

/// Opens `LanguageScreen` for a returning player who wants to switch —
/// `LanguageScreen` itself tells FTUE and this case apart via
/// `hasChosenLanguageProvider`, so this tile only has to navigate there.
///
/// Shared between the profile screen and the settings screen: both are
/// reasonable places to expect a language switch, and the tile is identical
/// either way, so it is a real widget rather than two copies of the same
/// `Row`.
class LanguageTile extends ConsumerWidget {
  const LanguageTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final selected = ref.watch(selectedLanguageProvider);

    return MetaCard(
      child: InkWell(
        borderRadius: AppTokens.borderRadius16,
        onTap: () => context.go(const LanguageRoute().location),
        child: Row(
          children: [
            Icon(Icons.language, color: tokens.colors.onSurfaceMuted),
            const SizedBox(width: AppTokens.space12),
            Expanded(
              child: Text(
                l10n.languageSectionTitle,
                style: AppTypography.uiTextStyle(
                  Language.english,
                  UiRole.body,
                  color: tokens.colors.onSurface,
                ),
              ),
            ),
            // The endonym, not a localized name — same rule as the picker
            // itself (CLAUDE.md → Localization): a player who reads only
            // Urdu still has to recognise their own language's name.
            Text(
              selected.endonym,
              style: AppTypography.uiTextStyle(
                selected,
                UiRole.body,
                color: tokens.colors.onSurfaceMuted,
              ),
            ),
            const SizedBox(width: AppTokens.space4),
            Icon(Icons.chevron_right, color: tokens.colors.onSurfaceMuted),
          ],
        ),
      ),
    );
  }
}
