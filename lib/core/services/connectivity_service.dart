import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Polls real connectivity every 5 s using an actual TCP lookup against a
/// reliable host. Pure `dart:io` — no extra package needed.
///
/// Consumers: `ref.watch(connectivityProvider)` → `AsyncValue<bool>` (true = online).
/// Use `ref.watch(isOnlineProvider)` for a simple `bool` with false as default.
final connectivityProvider = StreamProvider<bool>((ref) {
  return _connectivityStream();
});

/// Convenience: plain `bool`, never throws, defaults to `true` while loading.
final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityProvider).value ?? true;
});

Stream<bool> _connectivityStream() async* {
  // Emit immediately, then poll every 5 s.
  yield await _check();
  await for (final _ in Stream.periodic(const Duration(seconds: 5))) {
    yield await _check();
  }
}

Future<bool> _check() async {
  try {
    final result = await InternetAddress.lookup('google.com')
        .timeout(const Duration(seconds: 4));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}
