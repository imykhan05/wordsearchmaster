import 'package:flutter/widgets.dart';

import '../widgets/stub_screen.dart';

/// The core gameplay screen — grid, gesture layer, scoring. Real
/// implementation lands across P04–P07.
class GameScreen extends StatelessWidget {
  const GameScreen({required this.levelId, super.key});

  final String levelId;

  @override
  Widget build(BuildContext context) {
    return StubScreen(title: 'Game', subtitle: 'levelId = $levelId');
  }
}
