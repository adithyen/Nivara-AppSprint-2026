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
/// with sound-level streaming and multilingual locale routing.
class VoiceRecognitionService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  VoiceState _state = VoiceState.idle;

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
          debugPrint('[VoiceRecognitionService] Speech error: ${val.errorMsg}');
          _state = VoiceState.error;
          onStateChanged?.call(_state);
          onError?.call(val.errorMsg);
        },
        onStatus: (status) {
          debugPrint('[VoiceRecognitionService] Speech status: $status');
          if (status == 'listening') {
            _isListening = true;
            _state = VoiceState.listening;
            onStateChanged?.call(_state);
          } else if (status == 'notListening' || status == 'done') {
            _isListening = false;
            _state = VoiceState.idle;
            onStateChanged?.call(_state);
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

  /// Starts listening to microphone input in the specified language.
  Future<bool> startListening({
    VoiceLanguage language = VoiceLanguage.en,
    required Function(String text, bool isFinal) onResult,
    Function(double soundLevel)? onSoundLevel,
    Function(VoiceState)? onStateChanged,
  }) async {
    if (!_isInitialized) {
      final ready = await initialize(onStateChanged: onStateChanged);
      if (!ready) return false;
    }

    try {
      _isListening = true;
      _state = VoiceState.listening;
      onStateChanged?.call(_state);

      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords;
          final isFinal = result.finalResult;
          onResult(words, isFinal);
        },
        onSoundLevelChange: onSoundLevel,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
          localeId: language.localeId,
          listenFor: const Duration(seconds: 40),
          pauseFor: const Duration(seconds: 4),
        ),
      );

      return true;
    } catch (e) {
      debugPrint('[VoiceRecognitionService] Start listen error: $e');
      _isListening = false;
      _state = VoiceState.error;
      onStateChanged?.call(_state);
      return false;
    }
  }

  /// Stops listening and commits the recognition stream.
  Future<void> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
      _state = VoiceState.completed;
    }
  }

  /// Cancels listening and clears active buffers.
  Future<void> cancel() async {
    await _speech.cancel();
    _isListening = false;
    _state = VoiceState.idle;
  }

  /// Simulates speech input for testing or platforms without active speech recognition hardware.
  Future<void> simulateDictation({
    required String text,
    required Function(String text, bool isFinal) onResult,
    Function(double soundLevel)? onSoundLevel,
  }) async {
    final words = text.split(' ');
    String current = '';
    for (int i = 0; i < words.length; i++) {
      await Future.delayed(const Duration(milliseconds: 140));
      current += (i == 0 ? '' : ' ') + words[i];
      onSoundLevel?.call((i % 5 + 3) * 1.6);
      onResult(current, i == words.length - 1);
    }
  }
}
