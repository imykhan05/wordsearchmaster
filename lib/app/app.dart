import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

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
      // TODO(P02): replace with AppTokens-driven light/dark ThemeData.
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFE8A33D),
      ),
      routerConfig: router,
    );
  }
}
