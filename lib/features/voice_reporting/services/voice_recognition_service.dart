import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/voice_reporting_models.dart';

final voiceRecognitionServiceProvider = Provider<VoiceRecognitionService>((ref) {
  final service = VoiceRecognitionService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

/// High-performance speech recognition service wrapping speech_to_text
/// with sound-level streaming, continuous multi-sentence dictation,
/// intelligent multilingual locale routing, and leak-proof lifecycle management.
class VoiceRecognitionService with WidgetsBindingObserver {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  VoiceState _state = VoiceState.idle;
  int _sessionId = 0;

  String _accumulatedText = '';
  String _currentSessionText = '';
  VoiceLanguage _activeLanguage = VoiceLanguage.auto;
  Function(String text, bool isFinal)? _activeOnResult;
  Function(double soundLevel)? _activeOnSoundLevel;
  Function(VoiceState)? _activeOnStateChanged;
  Timer? _resumeDebounceTimer;

  VoiceRecognitionService() {
    WidgetsBinding.instance.addObserver(this);
  }

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  VoiceState get state => _state;
  String get accumulatedText => _accumulatedText;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app is backgrounded, paused, or minimized to home screen:
    // HARD STOP the microphone immediately so no audio or native beeps can leak!
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      debugPrint('[VoiceRecognitionService] App inactive/paused ($state). Halting speech engine immediately.');
      cancelSync();
    }
  }

  /// Initializes the speech engine and requests microphone permission if needed.
  Future<bool> initialize({
    Function(VoiceState)? onStateChanged,
    Function(String)? onError,
  }) async {
    if (_isInitialized) return true;

    try {
      final micPerm = await Permission.microphone.request();
      if (!micPerm.isGranted) {
        _state = VoiceState.error;
        onStateChanged?.call(_state);
        onError?.call('Microphone permission not granted');
        return false;
      }

      _isInitialized = await _speech.initialize(
        onError: (val) {
          debugPrint('[VoiceRecognitionService] Speech error: ${val.errorMsg}, permanent: ${val.permanent}');
          // If silence timeout or no match: user stopped speaking. Stop gracefully without infinite looping!
          if (val.errorMsg == 'error_speech_timeout' || val.errorMsg == 'error_no_match') {
            _resumeDebounceTimer?.cancel();
            _resumeDebounceTimer = null;
            if (_isListening) {
              _isListening = false;
              if (_currentSessionText.trim().isNotEmpty) {
                _accumulatedText = _accumulatedText.isEmpty
                    ? _currentSessionText.trim()
                    : '$_accumulatedText ${_currentSessionText.trim()}';
                _currentSessionText = '';
                _state = VoiceState.completed;
              } else {
                _state = _accumulatedText.isNotEmpty ? VoiceState.completed : VoiceState.idle;
              }
              _activeOnStateChanged?.call(_state);
            }
            return;
          }
          if (val.errorMsg == 'error_busy') {
            return;
          }
          if (val.permanent) {
            _resumeDebounceTimer?.cancel();
            _resumeDebounceTimer = null;
            _isListening = false;
            _state = VoiceState.error;
            onStateChanged?.call(_state);
            onError?.call(val.errorMsg);
          }
        },
        onStatus: (status) {
          debugPrint('[VoiceRecognitionService] Speech status: $status');
          if (status == 'listening') {
            if (!_isListening) {
              // Stale Android native session started after cancel was requested: force abort!
              try {
                _speech.cancel();
              } catch (_) {}
              return;
            }
            _state = VoiceState.listening;
            _activeOnStateChanged?.call(_state);
          } else if (status == 'notListening' || status == 'done') {
            _resumeDebounceTimer?.cancel();
            _resumeDebounceTimer = null;
            if (!_isListening) {
              _state = VoiceState.idle;
              _activeOnStateChanged?.call(_state);
              return;
            }
            // Speech finished naturally
            if (_currentSessionText.trim().isNotEmpty) {
              _accumulatedText = _accumulatedText.isEmpty
                  ? _currentSessionText.trim()
                  : '$_accumulatedText ${_currentSessionText.trim()}';
              _currentSessionText = '';
              _isListening = false;
              _state = VoiceState.completed;
              _activeOnStateChanged?.call(_state);
            } else {
              _isListening = false;
              _state = _accumulatedText.isNotEmpty ? VoiceState.completed : VoiceState.idle;
              _activeOnStateChanged?.call(_state);
            }
          }
        },
      );

      return _isInitialized;
    } catch (e) {
      debugPrint('[VoiceRecognitionService] Init exception: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Resolves the optimal speech locale immediately without blocking broadcasts.
  String? _resolveLocale(VoiceLanguage language) {
    if (language == VoiceLanguage.auto) {
      // Return null so Android SpeechRecognizer uses the device default system locale immediately!
      return null;
    }
    return language.localeId;
  }

  /// Starts listening to microphone input in the specified language.
  Future<bool> startListening({
    VoiceLanguage language = VoiceLanguage.auto,
    required Function(String text, bool isFinal) onResult,
    Function(double soundLevel)? onSoundLevel,
    Function(VoiceState)? onStateChanged,
    String? existingText,
  }) async {
    final session = ++_sessionId;

    if (!_isInitialized) {
      final ready = await initialize(onStateChanged: onStateChanged);
      if (!ready || session != _sessionId) return false;
    }

    if (session != _sessionId) return false;

    _accumulatedText = existingText?.trim() ?? '';
    _currentSessionText = '';
    _activeLanguage = language;
    _activeOnResult = onResult;
    _activeOnSoundLevel = onSoundLevel;
    _activeOnStateChanged = onStateChanged;
    _isListening = true;
    _state = VoiceState.listening;
    onStateChanged?.call(_state);

    return _startListeningInternal(session: session);
  }

  Future<bool> _startListeningInternal({int? session}) async {
    if (!_isListening) return false;
    if (session != null && session != _sessionId) return false;

    try {
      final localeId = _resolveLocale(_activeLanguage);
      debugPrint('[VoiceRecognitionService] Starting listen (lang: ${_activeLanguage.name}, localeId: $localeId, session: $_sessionId)');

      _resumeDebounceTimer?.cancel();
      _resumeDebounceTimer = null;

      await _speech.listen(
        onResult: (result) {
          if (!_isListening) return;
          debugPrint('[VoiceRecognitionService] onResult: "${result.recognizedWords}", final: ${result.finalResult}');
          _currentSessionText = result.recognizedWords;
          final fullText = _accumulatedText.isEmpty
              ? _currentSessionText
              : '$_accumulatedText $_currentSessionText';

          _activeOnResult?.call(fullText, result.finalResult);

          if (result.finalResult) {
            _accumulatedText = fullText.trim();
            _currentSessionText = '';
          }
        },
        onSoundLevelChange: (level) {
          if (_isListening) {
            _activeOnSoundLevel?.call(level);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
          localeId: localeId,
          listenFor: const Duration(seconds: 90),
          pauseFor: const Duration(seconds: 4),
        ),
      );

      // Check if cancelled while waiting for _speech.listen
      if (!_isListening || (session != null && session != _sessionId)) {
        try {
          await _speech.cancel();
        } catch (_) {}
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('[VoiceRecognitionService] Start listen error: $e');
      return false;
    }
  }

  /// Stops listening and commits the recognition stream.
  Future<void> stopListening() async {
    _resumeDebounceTimer?.cancel();
    _resumeDebounceTimer = null;
    _isListening = false;
    if (_speech.isListening) {
      try {
        await _speech.stop();
      } catch (_) {}
    }
    if (_currentSessionText.trim().isNotEmpty) {
      _accumulatedText = _accumulatedText.isEmpty
          ? _currentSessionText.trim()
          : '$_accumulatedText ${_currentSessionText.trim()}';
      _currentSessionText = '';
    }
    _state = VoiceState.completed;
    _activeOnStateChanged?.call(_state);
  }

  /// Immediately and synchronously halts listening, tears down native engine,
  /// and wipes callbacks so no background or post-dismiss audio triggers.
  void cancelSync() {
    _sessionId++;
    _resumeDebounceTimer?.cancel();
    _resumeDebounceTimer = null;
    _isListening = false;
    _accumulatedText = '';
    _currentSessionText = '';
    _activeOnResult = null;
    _activeOnSoundLevel = null;
    _activeOnStateChanged = null;
    _state = VoiceState.idle;
    try {
      _speech.cancel();
    } catch (e) {
      debugPrint('[VoiceRecognitionService] cancelSync error: $e');
    }
  }

  /// Cancels listening and clears active buffers.
  Future<void> cancel() async {
    cancelSync();
  }

  /// Completely clears recognized buffers (both accumulated and current phrase),
  /// and if actively listening, immediately cycles the native SpeechRecognizer
  /// so Android's internal result buffer is completely wiped clean.
  Future<void> clearBuffer({bool restartIfListening = false}) async {
    _accumulatedText = '';
    _currentSessionText = '';
    if (restartIfListening && _isListening) {
      final session = ++_sessionId;
      try {
        await _speech.cancel();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 80));
      if (_isListening && session == _sessionId) {
        await _startListeningInternal(session: session);
      }
    }
  }

  /// Updates the base accumulated text when the user manually types or edits
  /// the transcript in the UI, keeping speech continuation aligned.
  void updateBaseText(String text) {
    _accumulatedText = text.trim();
    _currentSessionText = '';
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cancelSync();
  }
}
