import '../../l10n/app_localizations.dart';

/// Localizes a content-pack category key ("animals") for display.
///
/// The category names themselves are content-side keys (P10 writes them into
/// every `WordEntry`) rather than translated strings, so both the collections
/// grid and the Collector achievement popup shared the same TODO(P17/P21) —
/// this is the one place that resolves it, so a category can never be
/// localized one way on one screen and left raw on another.
///
/// Falls back to the raw key for anything unrecognised rather than throwing:
/// a category added to the content pack without a matching ARB entry should
/// degrade to readable English, not crash the screen showing it.
String categoryLabel(AppLocalizations l10n, String category) =>
    switch (category) {
      'nature' => l10n.categoryNature,
      'animals' => l10n.categoryAnimals,
      'food' => l10n.categoryFood,
      'colors' => l10n.categoryColors,
      'family' => l10n.categoryFamily,
      'body' => l10n.categoryBody,
      'home' => l10n.categoryHome,
      'school' => l10n.categorySchool,
      'sports' => l10n.categorySports,
      'weather' => l10n.categoryWeather,
      'professions' => l10n.categoryProfessions,
      'numbers' => l10n.categoryNumbers,
      _ => category,
    };
