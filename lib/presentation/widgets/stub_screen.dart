import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FlavorBadge(),
              const SizedBox(height: 20),
              Text(
                'WORD SEARCH MASTER',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 28),
              const _RouteNav(),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteNav extends StatelessWidget {
  const _RouteNav();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
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
