import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config/app_config.dart';

/// Shows which flavor is running, in every screen, starting with the very
/// first frame. This is the whole point of P01's acceptance test: dev/stg
/// must be unmistakable at a glance so a tester never confuses a build with
/// prod (see CLAUDE.md → Never do: dev must never serve a real ad unit).
class FlavorBadge extends ConsumerWidget {
  const FlavorBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _colorFor(config.flavor),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        config.flavorName,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.4,
          fontSize: 12,
        ),
      ),
    );
  }

  Color _colorFor(Flavor flavor) => switch (flavor) {
    Flavor.dev => Colors.deepOrange,
    Flavor.stg => Colors.indigo,
    Flavor.prod => Colors.green.shade700,
  };
}
