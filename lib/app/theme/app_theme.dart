import 'package:flutter/material.dart';

import '../../domain/text/language.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// Builds [ThemeData] from [AppTokens]. Widgets should read tokens directly
/// via `AppTokens.of(context)`; this exists so Material's own widgets
/// (buttons, dialogs, scrollbars) pick up the palette too.
abstract final class AppTheme {
  static ThemeData dark({Language language = Language.english}) =>
      _build(AppTokens.dark, language);

  static ThemeData light({Language language = Language.english}) =>
      _build(AppTokens.light, language);

  static ThemeData _build(AppTokens tokens, Language language) {
    final colors = tokens.colors;

    final scheme = ColorScheme(
      brightness: tokens.brightness,
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      secondary: colors.info,
      onSecondary: colors.onPrimary,
      error: colors.warn,
      onError: colors.onPrimary,
      surface: colors.surface,
      onSurface: colors.onSurface,
      surfaceContainerHighest: colors.surfaceHigh,
      outline: colors.outline,
      outlineVariant: colors.outlineSoft,
      shadow: colors.shadow,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: tokens.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.surface,
      dividerColor: colors.outline,
      shadowColor: colors.shadow,
      fontFamily: _defaultFamily(language),
      textTheme: _textTheme(language, colors),
      extensions: [tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: colors.primary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.uiTextStyle(
          language,
          UiRole.title,
          color: colors.onSurface,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outline,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: tokens.elevation1.surface,
        shadowColor: colors.shadow,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: AppTokens.borderRadius16,
        ),
        margin: EdgeInsets.zero,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          side: BorderSide(color: colors.outline),
          shape: const RoundedRectangleBorder(
            borderRadius: AppTokens.borderRadius8,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space16,
            vertical: AppTokens.space12,
          ),
          textStyle: AppTypography.uiTextStyle(language, UiRole.label),
          minimumSize: const Size(0, AppTokens.minTouchTarget),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          shape: const RoundedRectangleBorder(
            borderRadius: AppTokens.borderRadius8,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space24,
            vertical: AppTokens.space12,
          ),
          textStyle: AppTypography.uiTextStyle(language, UiRole.label),
          minimumSize: const Size(0, AppTokens.minTouchTarget),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          textStyle: AppTypography.uiTextStyle(language, UiRole.label),
          minimumSize: const Size(0, AppTokens.minTouchTarget),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.elevation3.surface,
        contentTextStyle: AppTypography.uiTextStyle(
          language,
          UiRole.body,
          color: colors.onSurface,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: AppTokens.borderRadius8,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static String _defaultFamily(Language language) => switch (language) {
    // Body-class default: Naskh, not Nastaliq. Nastaliq is opted into per
    // role via AppTypography.uiTextStyle.
    Language.urdu => AppFonts.naskh,
    Language.hindi => AppFonts.devanagari,
    Language.english => AppFonts.latin,
  };

  static TextTheme _textTheme(Language language, AppColors colors) {
    TextStyle style(UiRole role, Color color) =>
        AppTypography.uiTextStyle(language, role, color: color);

    return TextTheme(
      displayLarge: style(UiRole.display, colors.onSurface),
      displayMedium: style(UiRole.display, colors.onSurface),
      displaySmall: style(UiRole.heading, colors.onSurface),
      headlineLarge: style(UiRole.heading, colors.onSurface),
      headlineMedium: style(UiRole.heading, colors.onSurface),
      headlineSmall: style(UiRole.heading, colors.onSurface),
      titleLarge: style(UiRole.title, colors.onSurface),
      titleMedium: style(UiRole.title, colors.onSurface),
      titleSmall: style(UiRole.title, colors.onSurfaceMuted),
      bodyLarge: style(UiRole.body, colors.onSurface),
      bodyMedium: style(UiRole.body, colors.onSurfaceMuted),
      bodySmall: style(UiRole.caption, colors.onSurfaceMuted),
      labelLarge: style(UiRole.label, colors.onSurface),
      labelMedium: style(UiRole.label, colors.onSurfaceMuted),
      labelSmall: style(UiRole.caption, colors.onSurfaceFaint),
    );
  }
}
