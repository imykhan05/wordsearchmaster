import 'package:flutter/widgets.dart';

import '../widgets/stub_screen.dart';

/// FTUE entry point (Chapter 02): splash lands here directly, no login, no
/// permission dialog, no ad. Real language picker lands in P12.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) => const StubScreen(title: 'Language');
}
