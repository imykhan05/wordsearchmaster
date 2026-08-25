import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config/app_config.dart';
import '../../app/language/selected_language.dart';
import '../../app/theme/theme.dart';
import '../../domain/grid/cell.dart';
import '../../domain/grid/grid_directions.dart';
import '../../domain/grid/grid_generator.dart';
import '../../domain/grid/grid_result.dart';
import '../../domain/grid/selection_resolver.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../game/game_grid.dart';
import '../game/grid_geometry.dart';
import '../game/particles.dart';

/// The core gameplay screen.
///
/// P06 SCOPE: this wires the rendering and gesture layers to a real generated
/// grid so the engine can be played and profiled. The score counter, hint
/// button, pause sheet, level-complete card and the Zeigarnik pre-load of the
/// next level all land in P07, along with the GameController that replaces the
/// local state below.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({required this.levelId, super.key});

  final String levelId;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  /// TODO(P10): comes from the content pack. Inline here only so P06 has a
  /// real grid to render and profile.
  static const Map<Language, List<String>> _demoWords = {
    Language.english: [
      'WATER',
      'STONE',
      'RIVER',
      'FOREST',
      'LIGHT',
      'EARTH',
      'STORM',
      'SEED',
    ],
    Language.urdu: [
      'پانی',
      'بادل',
      'ہوا',
      'زمین',
      'درخت',
      'دریا',
      'سورج',
      'برف',
    ],
    Language.hindi: [
      'पानी',
      'बादल',
      'हवा',
      'धरती',
      'नदी',
      'सूरज',
      'रात',
      'तारा',
    ],
  };

  final ParticleController _particles = ParticleController();

  GridResult? _grid;
  Language? _builtFor;
  final List<String> _found = [];
  final List<List<Cell>> _foundCells = [];

  int get _levelNumber => int.tryParse(widget.levelId) ?? 1;

  @override
  void dispose() {
    _particles.dispose();
    super.dispose();
  }

  GridResult _buildGrid(Language language) {
    final level = _levelNumber;
    return GridGenerator.generate(
      // The level number IS the seed here, so the same level always rebuilds
      // the same grid. P10 stores a real per-level seed.
      seed: level * 7919,
      size: level <= 5
          ? 6
          : level <= 20
          ? 8
          : level <= 60
          ? 10
          : 12,
      words: _demoWords[language]!,
      lang: language,
      allowedDirections: GridDirections.forLevel(language, level),
    );
  }

  void _onSelectionReleased(SelectionState state, GridGeometry geometry) {
    final grid = _grid;
    if (grid == null) return;

    final language = ref.read(selectedLanguageProvider);
    final resolver = SelectionResolver(size: grid.size);

    final outcome = resolver.release(
      state: state,
      grid: grid.cells,
      remainingWords: grid.placements.keys.where((w) => !_found.contains(w)),
      language: language,
    );

    if (outcome.matchedWord == null) return;

    final tokens = AppTokens.of(context);
    final colorIndex = _found.length % tokens.colors.foundWord.length;

    setState(() {
      _found.add(outcome.matchedWord!);
      _foundCells.add(outcome.cells);
    });

    // Burst from the middle of the word, per Ch03.
    final first = geometry.cellCenter(outcome.cells.first);
    final last = geometry.cellCenter(outcome.cells.last);
    _particles.burst(
      origin: Offset((first.dx + last.dx) / 2, (first.dy + last.dy) / 2),
      color: tokens.colors.foundWord[colorIndex],
      seed: outcome.matchedWord.hashCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(selectedLanguageProvider);
    final tokens = AppTokens.of(context);
    final isDev = ref.watch(appConfigProvider).flavor == Flavor.dev;

    if (_grid == null || _builtFor != language) {
      _grid = _buildGrid(language);
      _builtFor = language;
      _found.clear();
      _foundCells.clear();
    }
    final grid = _grid!;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).gameLevel(widget.levelId)),
      ),
      // No banner ad on this screen, ever (CLAUDE.md → Never do).
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.space16),
                child: GameGrid(
                  cells: grid.cells,
                  language: language,
                  foundWordCells: _foundCells,
                  onSelectionReleased: _onSelectionReleased,
                  particleController: _particles,
                  showPerfOverlay: isDev,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTokens.space16),
              child: Wrap(
                spacing: AppTokens.space8,
                runSpacing: AppTokens.space8,
                alignment: WrapAlignment.center,
                children: [
                  for (final word in grid.placements.keys)
                    _WordChip(
                      word: word,
                      language: language,
                      found: _found.contains(word),
                      color:
                          tokens.colors.foundWord[_found.indexOf(word) %
                              tokens.colors.foundWord.length],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A target word, shown in its CONNECTED display form — the shape the player
/// maps onto the isolated letters in the grid (Ch04).
class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.word,
    required this.language,
    required this.found,
    required this.color,
  });

  final String word;
  final Language language;
  final bool found;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space12,
        vertical: AppTokens.space4,
      ),
      decoration: BoxDecoration(
        color: found
            ? color.withValues(alpha: 0.22)
            : tokens.colors.surfaceElevated,
        borderRadius: AppTokens.borderRadius16,
        border: Border.all(color: found ? color : tokens.colors.outline),
      ),
      child: Text(
        word,
        style:
            AppTypography.uiTextStyle(
              language,
              UiRole.wordChip,
              color: found
                  ? tokens.colors.onSurfaceMuted
                  : tokens.colors.onSurface,
            ).copyWith(
              // TODO(P09): replace with the animated left-to-right strike draw.
              decoration: found ? TextDecoration.lineThrough : null,
              decorationColor: color,
              decorationThickness: 2,
            ),
      ),
    );
  }
}
