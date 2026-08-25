import 'package:flutter/widgets.dart';

import '../../domain/grid/grid_vector.dart';
import '../../domain/text/language.dart';
import '../theme/app_typography.dart';

/// The Flutter-typed view of a [Language].
///
/// These live here rather than on the enum because `Locale`, `TextDirection`
/// and `Offset` all come from `dart:ui`, and `lib/domain/` has to stay
/// runnable as plain Dart (CLAUDE.md → Architecture). Font families live here
/// for the same reason plus a better one: which typeface renders a script is
/// a presentation decision, and the domain has no business knowing it.
extension LanguageX on Language {
  /// The locale to hand to `MaterialApp`, matching the ARB file suffix.
  Locale get locale => Locale(code);

  /// Reading direction, driving the app-wide [Directionality].
  TextDirection get textDirection =>
      isRtl ? TextDirection.rtl : TextDirection.ltr;

  /// The direction a horizontally-placed word runs, as a Flutter [Offset] —
  /// `Offset(-1, 0)` for Urdu, `Offset(1, 0)` otherwise.
  ///
  /// The grid engine itself uses the integer [Language.primaryDirection]; this
  /// is for painting and hit-testing, which work in logical pixels.
  Offset get gridPrimaryDirection => primaryDirection.toOffset();

  /// Grid-cell typeface. Never Nastaliq — see [AppTypography.gridTextStyle].
  String get gridFontFamily => AppTypography.gridFontFamily(this);

  /// Body-class UI typeface. Naskh for Urdu; display-class roles opt into
  /// Nastaliq through [AppTypography.uiTextStyle].
  String get uiFontFamily => AppTypography.uiFontFamily(this);
}

extension GridVectorX on GridVector {
  /// The same step as a Flutter [Offset], for painting and gesture maths.
  Offset toOffset() => Offset(dx.toDouble(), dy.toDouble());
}
