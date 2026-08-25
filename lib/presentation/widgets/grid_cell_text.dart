import 'package:flutter/material.dart';

import '../../app/theme/theme.dart';
import '../../domain/text/language.dart';

/// A single grapheme rendered as a grid cell letter.
///
/// Two rules are baked in so no call site can forget them:
///  * the style comes from [AppTypography.gridTextStyle], which never returns
///    Nastaliq;
///  * text scaling is disabled ([AppTypography.gridTextScaler]) — the grid
///    scales via cell size, and letting the OS scale on top overflows cells.
///    Every *other* piece of text in the app does respect the system scale.
///
/// P06 replaces the grid's rendering with a single [CustomPainter]; this
/// widget stays for the Style Gallery, goldens, and one-off cells outside the
/// grid (FTUE illustration, word previews).
class GridCellText extends StatelessWidget {
  const GridCellText({
    required this.grapheme,
    required this.language,
    this.cellSize = AppTypography.defaultGridCellSize,
    this.color,
    this.background,
    this.borderColor,
    this.borderWidth,
    super.key,
  });

  /// A single grapheme cluster — `پ`, `पा`, `W`. Never a code unit slice.
  final String grapheme;
  final Language language;
  final double cellSize;
  final Color? color;
  final Color? background;
  final Color? borderColor;
  final double? borderWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      width: cellSize,
      height: cellSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? tokens.colors.surfaceElevated,
        borderRadius: AppTokens.borderRadius4,
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: borderWidth ?? 1.5),
      ),
      // A wide Devanagari akshara shrinks to fit instead of overflowing.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          grapheme,
          textScaler: AppTypography.gridTextScaler,
          style: AppTypography.gridTextStyle(
            language,
            cellSize: cellSize,
            color: color ?? tokens.colors.onSurface,
          ),
        ),
      ),
    );
  }
}
