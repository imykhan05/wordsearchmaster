import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/theme.dart';

/// The app root. Everything flavor-specific is already resolved into
/// [appConfigProvider] by the time this builds — this widget itself must
/// stay flavor-agnostic.
class WordSearchMasterApp extends ConsumerWidget {
  const WordSearchMasterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Word Search Master',
      debugShowCheckedModeBanner: false,
      // Dark is the product default; light is offered for players who prefer
      // it and doubles as the high-contrast option (Ch03). P03 rebuilds these
      // per selected Language so the default font family follows the script.
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
