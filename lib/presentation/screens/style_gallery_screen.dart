import 'package:flutter/material.dart';

import '../../app/theme/theme.dart';
import '../../domain/text/language.dart';
import '../widgets/grid_cell_text.dart';

/// DEV-FLAVOR ONLY. Registered in `router.dart` only when the running flavor
/// is [Flavor.dev], so it can never ship to a player.
///
/// Every token, both themes, and all three scripts on one scrollable page.
/// The point is regression visibility: a font swap, a cell-metric change or a
/// Flutter upgrade that breaks Urdu or Hindi rendering shows up here at a
/// glance, long before it reaches a golden test or a store review.
class StyleGalleryScreen extends StatefulWidget {
  const StyleGalleryScreen({super.key});

  @override
  State<StyleGalleryScreen> createState() => _StyleGalleryScreenState();
}

class _StyleGalleryScreenState extends State<StyleGalleryScreen> {
  Brightness _brightness = Brightness.dark;

  @override
  Widget build(BuildContext context) {
    final theme = _brightness == Brightness.dark
        ? AppTheme.dark()
        : AppTheme.light();

    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final tokens = AppTokens.of(context);
          return Scaffold(
            backgroundColor: tokens.colors.background,
            appBar: AppBar(
              title: const Text('Style Gallery'),
              actions: [
                IconButton(
                  tooltip: 'Toggle theme',
                  icon: Icon(
                    _brightness == Brightness.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                  ),
                  onPressed: () => setState(() {
                    _brightness = _brightness == Brightness.dark
                        ? Brightness.light
                        : Brightness.dark;
                  }),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(AppTokens.space16),
              children: const [
                _ReduceMotionBanner(),
                _Section(
                  title: 'Scripts',
                  caption:
                      'Word chip shows the CONNECTED form the player reads. '
                      'Grid cells show the ISOLATED graphemes they must find. '
                      'That mapping is the puzzle (Ch04).',
                  child: _ScriptSamples(),
                ),
                _Section(
                  title: 'Type scale',
                  caption:
                      'Every UI role, per script. Respects system text scale.',
                  child: _TypeScale(),
                ),
                _Section(
                  title: 'Colours — both themes',
                  caption:
                      'Shown side by side so a palette regression is obvious.',
                  child: _ColorPalettes(),
                ),
                _Section(
                  title: 'Found-word highlights',
                  caption:
                      'Colourblind-safe palette. Each also carries its own '
                      'border weight — colour is never the only cue.',
                  child: _FoundWordPalette(),
                ),
                _Section(title: 'Spacing', child: _SpacingScale()),
                _Section(title: 'Radii', child: _RadiiScale()),
                _Section(
                  title: 'Elevation',
                  caption: 'Surface tint + shadow, not shadow alone.',
                  child: _Elevations(),
                ),
                _Section(
                  title: 'Motion',
                  caption:
                      'Tap to play. All collapse to 0ms under reduce-motion.',
                  child: _MotionDemo(),
                ),
                SizedBox(height: AppTokens.space48),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Makes the reduce-motion state visible, so "durations are zero" can be
/// confirmed by eye and not just in a test.
class _ReduceMotionBanner extends StatelessWidget {
  const _ReduceMotionBanner();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final motion = Motion.of(context);
    final active = motion.disabled;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.space16),
      padding: const EdgeInsets.all(AppTokens.space12),
      decoration: BoxDecoration(
        color: active
            ? tokens.colors.warn.withValues(alpha: 0.14)
            : tokens.colors.surfaceElevated,
        borderRadius: AppTokens.borderRadius8,
        border: Border.all(
          color: active ? tokens.colors.warn : tokens.colors.outline,
        ),
      ),
      child: Text(
        active
            ? 'Reduce motion is ON — every duration resolves to 0ms.'
            : 'Reduce motion is off — instant ${motion.instant.inMilliseconds}ms · '
                  'quick ${motion.quick.inMilliseconds}ms · '
                  'base ${motion.base.inMilliseconds}ms · '
                  'slow ${motion.slow.inMilliseconds}ms',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.caption});

  final String title;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.space32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.headlineSmall),
          if (caption != null) ...[
            const SizedBox(height: AppTokens.space4),
            Text(caption!, style: textTheme.bodySmall),
          ],
          const SizedBox(height: AppTokens.space12),
          Container(height: 1, color: tokens.colors.outline),
          const SizedBox(height: AppTokens.space16),
          child,
        ],
      ),
    );
  }
}

/// One sample per language: the word as the player reads it, then the same
/// word broken into the graphemes that occupy grid cells.
class _ScriptSamples extends StatelessWidget {
  const _ScriptSamples();

  static const Map<Language, ({String word, String gloss})> _samples = {
    Language.urdu: (word: 'پانی', gloss: 'paani — water'),
    Language.hindi: (word: 'पानी', gloss: 'paani — water'),
    Language.english: (word: 'WATER', gloss: 'water'),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in _samples.entries) ...[
          _ScriptSample(
            language: entry.key,
            word: entry.value.word,
            gloss: entry.value.gloss,
          ),
          const SizedBox(height: AppTokens.space24),
        ],
      ],
    );
  }
}

class _ScriptSample extends StatelessWidget {
  const _ScriptSample({
    required this.language,
    required this.word,
    required this.gloss,
  });

  final Language language;
  final String word;
  final String gloss;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    // Grapheme clusters, never code points: "पानी" is 2 cells (पा, नी),
    // not 4 (Ch04, Masla 3).
    final graphemes = word.characters.toList();

    return Container(
      padding: const EdgeInsets.all(AppTokens.space16),
      decoration: BoxDecoration(
        color: tokens.elevation1.surface,
        borderRadius: AppTokens.borderRadius8,
        border: Border.all(color: tokens.colors.outlineSoft),
        boxShadow: tokens.elevation1.shadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${language.code.toUpperCase()} · ${language.isRtl ? 'RTL' : 'LTR'}',
                style: textTheme.labelSmall,
              ),
              const Spacer(),
              Text(
                '${graphemes.length} graphemes · ${word.length} code units',
                style: textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space12),

          Text('word chip (connected)', style: textTheme.labelSmall),
          const SizedBox(height: AppTokens.space4),
          Directionality(
            textDirection: language.isRtl
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: Text(
              word,
              style: AppTypography.uiTextStyle(
                language,
                UiRole.wordChip,
                color: tokens.colors.onSurface,
              ),
            ),
          ),

          const SizedBox(height: AppTokens.space16),
          Text('grid cells (isolated)', style: textTheme.labelSmall),
          const SizedBox(height: AppTokens.space8),
          Directionality(
            textDirection: language.isRtl
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: Wrap(
              spacing: AppTokens.space4,
              runSpacing: AppTokens.space4,
              children: [
                for (final grapheme in graphemes)
                  GridCellText(
                    grapheme: grapheme,
                    language: language,
                    cellSize: 44,
                  ),
              ],
            ),
          ),

          const SizedBox(height: AppTokens.space8),
          Text(gloss, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _TypeScale extends StatelessWidget {
  const _TypeScale();

  static const Map<Language, String> _specimen = {
    Language.urdu: 'لفظوں کی تلاش',
    Language.hindi: 'शब्द खोज',
    Language.english: 'Word Search',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in _specimen.entries) ...[
          Text(entry.key.code.toUpperCase(), style: textTheme.labelSmall),
          const SizedBox(height: AppTokens.space8),
          for (final role in UiRole.values)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.space8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 74,
                    child: Text(role.name, style: textTheme.labelSmall),
                  ),
                  Expanded(
                    child: Directionality(
                      textDirection: entry.key.isRtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: Text(
                        entry.value,
                        style: AppTypography.uiTextStyle(
                          entry.key,
                          role,
                          color: tokens.colors.onSurface,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    AppTypography.nastaliqRoles.contains(role) &&
                            entry.key == Language.urdu
                        ? 'nastaliq'
                        : '',
                    style: textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppTokens.space24),
        ],
      ],
    );
  }
}

class _ColorPalettes extends StatelessWidget {
  const _ColorPalettes();

  static List<({String name, Color Function(AppColors) pick})> get _entries => [
    (name: 'background', pick: (c) => c.background),
    (name: 'surface', pick: (c) => c.surface),
    (name: 'surfaceElevated', pick: (c) => c.surfaceElevated),
    (name: 'surfaceHigh', pick: (c) => c.surfaceHigh),
    (name: 'outline', pick: (c) => c.outline),
    (name: 'outlineSoft', pick: (c) => c.outlineSoft),
    (name: 'primary', pick: (c) => c.primary),
    (name: 'primaryDim', pick: (c) => c.primaryDim),
    (name: 'onPrimary', pick: (c) => c.onPrimary),
    (name: 'success', pick: (c) => c.success),
    (name: 'warn', pick: (c) => c.warn),
    (name: 'info', pick: (c) => c.info),
    (name: 'onSurface', pick: (c) => c.onSurface),
    (name: 'onSurfaceMuted', pick: (c) => c.onSurfaceMuted),
    (name: 'onSurfaceFaint', pick: (c) => c.onSurfaceFaint),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 130),
            Expanded(child: Text('dark', style: textTheme.labelSmall)),
            Expanded(child: Text('light', style: textTheme.labelSmall)),
          ],
        ),
        const SizedBox(height: AppTokens.space8),
        for (final entry in _entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.space4),
            child: Row(
              children: [
                SizedBox(
                  width: 130,
                  child: Text(entry.name, style: textTheme.labelSmall),
                ),
                Expanded(
                  child: _Swatch(color: entry.pick(AppTokens.darkColors)),
                ),
                const SizedBox(width: AppTokens.space8),
                Expanded(
                  child: _Swatch(color: entry.pick(AppTokens.lightColors)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppTokens.borderRadius4,
        border: Border.all(color: tokens.colors.outlineSoft),
      ),
    );
  }
}

class _FoundWordPalette extends StatelessWidget {
  const _FoundWordPalette();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Wrap(
      spacing: AppTokens.space8,
      runSpacing: AppTokens.space8,
      children: [
        for (var i = 0; i < tokens.colors.foundWord.length; i++)
          Column(
            children: [
              Container(
                width: 76,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.colors.foundWord[i].withValues(alpha: 0.30),
                  borderRadius: AppTokens.borderRadius16,
                  border: Border.all(
                    color: tokens.colors.foundWord[i],
                    width: AppTokens.foundWordBorderWidths[i],
                  ),
                ),
                child: Text('$i', style: textTheme.labelMedium),
              ),
              const SizedBox(height: AppTokens.space4),
              Text(
                '${AppTokens.foundWordBorderWidths[i]}px',
                style: textTheme.labelSmall,
              ),
            ],
          ),
      ],
    );
  }
}

class _SpacingScale extends StatelessWidget {
  const _SpacingScale();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        for (final space in AppTokens.spacingScale)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.space8),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text('${space.toInt()}', style: textTheme.labelSmall),
                ),
                Container(
                  width: space,
                  height: 20,
                  decoration: BoxDecoration(
                    color: tokens.colors.primary,
                    borderRadius: AppTokens.borderRadius4,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RadiiScale extends StatelessWidget {
  const _RadiiScale();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        for (final radius in AppTokens.radiusScale)
          Padding(
            padding: const EdgeInsets.only(right: AppTokens.space16),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: tokens.colors.surfaceHigh,
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: tokens.colors.outline),
                  ),
                ),
                const SizedBox(height: AppTokens.space4),
                Text('${radius.toInt()}', style: textTheme.labelSmall),
              ],
            ),
          ),
      ],
    );
  }
}

class _Elevations extends StatelessWidget {
  const _Elevations();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final elevations = tokens.elevations;

    return Row(
      children: [
        for (var i = 0; i < elevations.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: AppTokens.space16),
              child: Column(
                children: [
                  Container(
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: elevations[i].surface,
                      borderRadius: AppTokens.borderRadius8,
                      boxShadow: elevations[i].shadows,
                    ),
                    child: Text('${i + 1}', style: textTheme.titleMedium),
                  ),
                  const SizedBox(height: AppTokens.space4),
                  Text('elevation${i + 1}', style: textTheme.labelSmall),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MotionDemo extends StatefulWidget {
  const _MotionDemo();

  @override
  State<_MotionDemo> createState() => _MotionDemoState();
}

class _MotionDemoState extends State<_MotionDemo> {
  bool _moved = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final motion = Motion.of(context);

    final demos = <({String name, Duration duration, Curve curve})>[
      (name: 'instant · fade', duration: motion.instant, curve: Motion.fade),
      (name: 'quick · punch', duration: motion.quick, curve: Motion.punch),
      (name: 'base · settle', duration: motion.base, curve: Motion.settle),
      (name: 'slow · settle', duration: motion.slow, curve: Motion.settle),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final demo in demos)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.space12),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    '${demo.name}\n${demo.duration.inMilliseconds}ms',
                    style: textTheme.labelSmall,
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: _moved
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: demo.duration,
                      curve: demo.curve,
                      width: _moved ? 44 : 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _moved
                            ? tokens.colors.success
                            : tokens.colors.primary,
                        borderRadius: AppTokens.borderRadius4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppTokens.space8),
        FilledButton(
          onPressed: () => setState(() => _moved = !_moved),
          child: const Text('Play'),
        ),
      ],
    );
  }
}
