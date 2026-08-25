import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/config/app_config.dart';
import '../../app/theme/theme.dart';
import '../../l10n/app_localizations.dart';
import 'flavor_badge.dart';

/// Placeholder body shared by every route until its owning prompt (see
/// CLAUDE.md folder structure) builds the real screen. Includes a route
/// switcher purely as a dev convenience for smoke-testing go_router.
class StubScreen extends StatelessWidget {
  const StubScreen({required this.title, this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTokens.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FlavorBadge(),
              const SizedBox(height: AppTokens.space24),
              Text(
                AppLocalizations.of(context).appTitle,
                style: textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTokens.space8),
              Text(title, style: textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: AppTokens.space4),
                Text(subtitle!, style: textTheme.bodySmall),
              ],
              const SizedBox(height: AppTokens.space8),
              Text(
                AppLocalizations.of(context).comingSoon,
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: AppTokens.space32),
              const _RouteNav(),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteNav extends ConsumerWidget {
  const _RouteNav();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDev = ref.watch(appConfigProvider).flavor == Flavor.dev;

    return Wrap(
      spacing: AppTokens.space8,
      runSpacing: AppTokens.space8,
      alignment: WrapAlignment.center,
      children: [
        _navButton(context, 'Language', const LanguageRoute().location),
        _navButton(context, 'Home', const HomeRoute().location),
        _navButton(context, 'Journey', const JourneyRoute().location),
        _navButton(context, 'Game', const GameRoute('1').location),
        _navButton(context, 'Daily', const DailyRoute().location),
        _navButton(context, 'Leaderboard', const LeaderboardRoute().location),
        _navButton(context, 'Profile', const ProfileRoute().location),
        _navButton(context, 'Settings', const SettingsRoute().location),
        if (isDev)
          _navButton(
            context,
            'Style Gallery',
            const StyleGalleryRoute().location,
          ),
      ],
    );
  }

  Widget _navButton(BuildContext context, String label, String location) {
    return OutlinedButton(
      onPressed: () => context.go(location),
      child: Text(label),
    );
  }
}
