import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'router.dart';

/// Root widget: wires the router + theme into [MaterialApp.router].
class NivaraApp extends ConsumerWidget {
  const NivaraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: NivaraTheme.light,
      darkTheme: NivaraTheme.dark,
      routerConfig: router,
    );
  }
}
