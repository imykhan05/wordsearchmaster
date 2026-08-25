import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../widgets/stub_screen.dart';

/// The core gameplay screen — grid, gesture layer, scoring. Real
/// implementation lands across P04–P07.
class GameScreen extends StatelessWidget {
  const GameScreen({required this.levelId, super.key});

  final String levelId;

  @override
  Widget build(BuildContext context) {
    return StubScreen(title: AppLocalizations.of(context).gameLevel(levelId));
  }
}
