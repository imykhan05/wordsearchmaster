import 'package:flutter/widgets.dart';

import '../widgets/stub_screen.dart';

/// Server-authoritative scores only — see P14/P17.
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) => const StubScreen(title: 'Leaderboard');
}
