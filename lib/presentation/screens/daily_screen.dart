import 'package:flutter/widgets.dart';

import '../widgets/stub_screen.dart';

/// Seeded from the date, playable fully offline — see P11.
class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const StubScreen(title: 'Daily Challenge');
}
