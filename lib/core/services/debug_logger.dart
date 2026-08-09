import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// On-device file logger for Nivara.
///
/// The user asked for a *real* debugger that writes everything to a file under
/// `Download/nivara/logs/…` so map-load failures (and anything else) can be
/// inspected after the fact on the phone — no `flutter run` / logcat needed.
///
/// Behaviour:
///  * Every [log] line is timestamped and **flushed to disk immediately**, so a
///    crash still leaves a complete file ("updates its entire thing in file").
///  * Target directory, in priority order:
///      1. `/storage/emulated/0/Download/nivara/logs`  (the literal ask)
///      2. app external-files dir `…/Android/data/<pkg>/files/nivara/logs`
///         (always writable, needs no runtime permission)
///      3. app documents dir (last resort)
///    The first that accepts a probe write wins; [resolvedPath] records it so
///    the UI can show exactly where the log landed.
///  * A short in-memory ring buffer ([recent]) powers the on-screen debug
///    overlay on the map; [revision] ticks on every line so widgets repaint.
///  * All file I/O is guarded — logging must never crash the app.
class DebugLogger {
  DebugLogger._();
  static final DebugLogger instance = DebugLogger._();

  File? _file;
  String? _resolvedPath;
  bool _ready = false;
  final List<String> _ring = <String>[];
  final List<String> _pending = <String>[];
  static const int _ringMax = 250;

  /// Ticks on every appended line so `ValueListenableBuilder` can refresh the
  /// on-screen log overlay without polling.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Absolute path of the active log file, or a placeholder until [init] runs.
  String get resolvedPath => _resolvedPath ?? '(resolving log path…)';

  /// Most-recent lines (newest last), for the on-screen overlay.
  List<String> get recent => List<String>.unmodifiable(_ring);

  /// Resolve a writable log directory and open a fresh timestamped file.
  /// Safe to call once at startup; never throws.
  Future<void> init() async {
    if (_ready) return;
    final stamp = _fileStamp(DateTime.now());
    final candidates = await _candidateDirs();

    for (final dirPath in candidates) {
      try {
        final dir = Directory(dirPath);
        await dir.create(recursive: true);
        final file = File('$dirPath/nivara_$stamp.log');
        // Probe-write the header; if this throws we try the next candidate.
        file.writeAsStringSync(
          _header(dirPath),
          mode: FileMode.write,
          flush: true,
        );
        _file = file;
        _resolvedPath = file.path;
        _ready = true;
        break;
      } catch (_) {
        // Try the next candidate directory.
        continue;
      }
    }

    // Flush anything logged before the file was ready.
    if (_ready && _pending.isNotEmpty) {
      try {
        _file!.writeAsStringSync(
          _pending.join(),
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {/* ignore */}
      _pending.clear();
    }

    log('LOG', _ready
        ? 'Logger ready → $_resolvedPath'
        : 'Logger could NOT open any file; console-only.');
  }

  /// Append a timestamped `[tag] message` line. Flushes to disk immediately.
  void log(String tag, String message) {
    final line = '${_timeStamp(DateTime.now())} [$tag] $message\n';

    // In-memory ring for the on-screen overlay.
    _ring.add(line.trimRight());
    if (_ring.length > _ringMax) _ring.removeAt(0);

    // Persist (or buffer until the file is open).
    if (_ready && _file != null) {
      try {
        _file!.writeAsStringSync(line, mode: FileMode.append, flush: true);
      } catch (_) {/* never let logging crash the app */}
    } else {
      _pending.add(line);
    }

    if (kDebugMode) debugPrint('NIVARA $line'.trimRight());
    revision.value++;
  }

  /// Convenience for errors with an optional stack trace.
  void error(String tag, Object err, [StackTrace? stack]) {
    log(tag, 'ERROR: $err');
    if (stack != null) log(tag, stack.toString());
  }

  // ── internals ─────────────────────────────────────────────────────────────

  Future<List<String>> _candidateDirs() async {
    final out = <String>[];

    // 1) Literal public Download folder (what the user asked for). May be
    //    blocked by scoped storage on Android 11+, in which case we fall back.
    if (Platform.isAndroid) {
      out.add('/storage/emulated/0/Download/nivara/logs');
    }

    // 2) App external-files dir — always writable, no permission needed.
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) out.add('${ext.path}/nivara/logs');
    } catch (_) {/* not Android / unavailable */}

    // 3) App documents dir — last resort, always exists.
    try {
      final docs = await getApplicationDocumentsDirectory();
      out.add('${docs.path}/nivara/logs');
    } catch (_) {/* ignore */}

    return out;
  }

  String _header(String dirPath) {
    final now = DateTime.now();
    return '═══════════════════════════════════════════════\n'
        ' NIVARA debug log\n'
        ' opened : ${now.toIso8601String()}\n'
        ' dir    : $dirPath\n'
        ' note   : map/style/pin lifecycle + errors are logged here.\n'
        '═══════════════════════════════════════════════\n';
  }

  String _timeStamp(DateTime t) =>
      '${_pad2(t.hour)}:${_pad2(t.minute)}:${_pad2(t.second)}.${_pad3(t.millisecond)}';

  String _fileStamp(DateTime t) =>
      '${t.year}${_pad2(t.month)}${_pad2(t.day)}_'
      '${_pad2(t.hour)}${_pad2(t.minute)}${_pad2(t.second)}';

  static String _pad2(int n) => n.toString().padLeft(2, '0');
  static String _pad3(int n) => n.toString().padLeft(3, '0');
}
