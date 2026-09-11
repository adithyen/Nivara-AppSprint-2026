import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/voice_reporting_models.dart';

final voiceRecognitionServiceProvider = Provider<VoiceRecognitionService>((ref) {
  return VoiceRecognitionService();
});

/// High-performance speech recognition service wrapping speech_to_text
/// with sound-level streaming, continuous multi-sentence dictation,
/// and intelligent multilingual locale routing.
class VoiceRecognitionService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  VoiceState _state = VoiceState.idle;

  String _accumulatedText = '';
  String _currentSessionText = '';
  VoiceLanguage _activeLanguage = VoiceLanguage.auto;
  Function(String text, bool isFinal)? _activeOnResult;
  Function(double soundLevel)? _activeOnSoundLevel;
  Function(VoiceState)? _activeOnStateChanged;
  Timer? _resumeDebounceTimer;

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  VoiceState get state => _state;

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
          // Filter out harmless Android speech recognition timeouts/no-match
          if (val.errorMsg == 'error_no_match' ||
              val.errorMsg == 'error_speech_timeout' ||
              val.errorMsg == 'error_busy') {
            return;
          }
          if (val.permanent) {
            _isListening = false;
            _state = VoiceState.error;
            onStateChanged?.call(_state);
            onError?.call(val.errorMsg);
          }
        },
        onStatus: (status) {
          debugPrint('[VoiceRecognitionService] Speech status: $status');
          if (status == 'listening') {
            _state = VoiceState.listening;
            _activeOnStateChanged?.call(_state);
          } else if (status == 'notListening' || status == 'done') {
            if (_isListening) {
              // Seamless continuous listening: If the recognizer paused or finished a phrase,
              // auto-resume so multi-sentence speech flows continuously without cutting off!
              _scheduleAutoResume();
            } else {
              _state = VoiceState.idle;
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

  void _scheduleAutoResume() {
    _resumeDebounceTimer?.cancel();
    if (!_isListening) return;
    _resumeDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (_isListening && !_speech.isListening) {
        // Commit current phrase to accumulated buffer
        if (_currentSessionText.trim().isNotEmpty) {
          _accumulatedText = _accumulatedText.isEmpty
              ? _currentSessionText.trim()
              : '$_accumulatedText ${_currentSessionText.trim()}';
          _currentSessionText = '';
        }
        _startListeningInternal();
      }
    });
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
    if (!_isInitialized) {
      final ready = await initialize(onStateChanged: onStateChanged);
      if (!ready) return false;
    }

    _accumulatedText = existingText?.trim() ?? '';
    _currentSessionText = '';
    _activeLanguage = language;
    _activeOnResult = onResult;
    _activeOnSoundLevel = onSoundLevel;
    _activeOnStateChanged = onStateChanged;
    _isListening = true;
    _state = VoiceState.listening;
    onStateChanged?.call(_state);

    return _startListeningInternal();
  }

  Future<bool> _startListeningInternal() async {
    if (!_isListening) return false;

    try {
      final localeId = _resolveLocale(_activeLanguage);
      debugPrint('[VoiceRecognitionService] Starting listen (lang: ${_activeLanguage.name}, localeId: $localeId)');

      _resumeDebounceTimer?.cancel();

      await _speech.listen(
        onResult: (result) {
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
        onSoundLevelChange: _activeOnSoundLevel,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.confirmation,
          localeId: localeId,
          listenFor: const Duration(seconds: 90),
          pauseFor: const Duration(seconds: 4),
        ),
      );

      return true;
    } catch (e) {
      debugPrint('[VoiceRecognitionService] Start listen error: $e');
      return false;
    }
  }

  /// Stops listening and commits the recognition stream.
  Future<void> stopListening() async {
    _resumeDebounceTimer?.cancel();
    _isListening = false;
    if (_speech.isListening) {
      await _speech.stop();
    }
    _state = VoiceState.completed;
    _activeOnStateChanged?.call(_state);
  }

  /// Cancels listening and clears active buffers.
  Future<void> cancel() async {
    _resumeDebounceTimer?.cancel();
    _isListening = false;
    _accumulatedText = '';
    _currentSessionText = '';
    await _speech.cancel();
    _state = VoiceState.idle;
    _activeOnStateChanged?.call(_state);
  }
}
