import 'package:flutter/widgets.dart';

import '../widgets/stub_screen.dart';

/// Guest/Google identity, stats, achievements, account deletion — see P13/P21.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => const StubScreen(title: 'Profile');
}
