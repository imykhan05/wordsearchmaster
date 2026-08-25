import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config/app_config.dart';
import '../../app/theme/theme.dart';
import '../../domain/text/language.dart';

/// Shows which flavor is running, in every screen, starting with the very
/// first frame. This is the whole point of P01's acceptance test: dev/stg
/// must be unmistakable at a glance so a tester never confuses a build with
/// prod (see CLAUDE.md → Never do: dev must never serve a real ad unit).
class FlavorBadge extends ConsumerWidget {
  const FlavorBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final tokens = AppTokens.of(context);

    // Distinct hues so the three builds are never mistaken for each other on
    // a device that has all three installed side by side.
    final background = switch (config.flavor) {
      Flavor.dev => tokens.colors.warn,
      Flavor.stg => tokens.colors.info,
      Flavor.prod => tokens.colors.success,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space12,
        vertical: AppTokens.space4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTokens.borderRadius16,
      ),
      child: Text(
        config.flavorName,
        style: AppTypography.uiTextStyle(
          Language.english,
          UiRole.label,
          color: tokens.colors.onPrimary,
          weight: FontWeight.w700,
        ),
      ),
    );
  }
}
