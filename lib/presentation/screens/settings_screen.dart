import 'package:flutter/widgets.dart';

import '../widgets/stub_screen.dart';

/// Sound, haptics, notifications, language, accessibility toggles — see P21.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const StubScreen(title: 'Settings');
}
