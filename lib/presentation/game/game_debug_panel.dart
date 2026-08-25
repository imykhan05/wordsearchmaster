import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/theme.dart';
import '../../application/game_controller.dart';
import '../../domain/text/language.dart';

/// DEV FLAVOR ONLY. Jump to any level or force any [GamePhase] without
/// playing to it — the fastest way to eyeball level 20 or the result card
/// without a 20-level run.
///
/// Its own expand/collapse and text field are ordinary [StatefulWidget]
/// concerns local to this one dev widget, not game state — the same
/// carve-out `PerfOverlay` (P06) already uses for its refresh timer.
/// Allowlisted in `tool/check_localized_strings.dart` alongside it: neither
/// ships to a player.
class GameDebugPanel extends ConsumerStatefulWidget {
  const GameDebugPanel({required this.level, super.key});

  final int level;

  @override
  ConsumerState<GameDebugPanel> createState() => _GameDebugPanelState();
}

class _GameDebugPanelState extends ConsumerState<GameDebugPanel> {
  late final TextEditingController _levelField = TextEditingController(
    text: '${widget.level}',
  );
  bool _expanded = false;

  @override
  void dispose() {
    _levelField.dispose();
    super.dispose();
  }

  void _jump() {
    final level = int.tryParse(_levelField.text);
    if (level == null || level < 1) return;
    ref.read(gameControllerProvider(widget.level).notifier).jumpToLevel(level);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final captionStyle = AppTypography.uiTextStyle(
      Language.english,
      UiRole.caption,
      color: tokens.colors.onSurfaceMuted,
    );

    if (!_expanded) {
      return _PanelChrome(
        tokens: tokens,
        child: IconButton(
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () => setState(() => _expanded = true),
          icon: Icon(Icons.bug_report, color: tokens.colors.onSurfaceMuted),
        ),
      );
    }

    return _PanelChrome(
      tokens: tokens,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('DEBUG', style: captionStyle),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _expanded = false),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: tokens.colors.onSurfaceMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.space8),
            Row(
              children: [
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: _levelField,
                    keyboardType: TextInputType.number,
                    style: captionStyle,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: AppTokens.space8,
                        vertical: AppTokens.space4,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: _jump,
                  icon: Icon(Icons.arrow_forward, color: tokens.colors.primary),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.space8),
            Wrap(
              spacing: AppTokens.space4,
              runSpacing: AppTokens.space4,
              children: [
                for (final phase in GamePhase.values)
                  ActionChip(
                    label: Text(phase.name, style: captionStyle),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: tokens.colors.surfaceHigh,
                    onPressed: () => ref
                        .read(gameControllerProvider(widget.level).notifier)
                        .debugForcePhase(phase),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelChrome extends StatelessWidget {
  const _PanelChrome({required this.tokens, required this.child});

  final AppTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tokens.colors.background.withValues(alpha: 0.9),
      borderRadius: AppTokens.borderRadius8,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 160),
        decoration: BoxDecoration(
          borderRadius: AppTokens.borderRadius8,
          border: Border.all(color: tokens.colors.outline),
        ),
        child: child,
      ),
    );
  }
}
