import 'package:flutter_tts/flutter_tts.dart';

/// In-app voice alert service using flutter_tts.
/// Speaks text through the device speaker without depending on
/// Android TalkBack or iOS VoiceOver.
class VoiceAlertService {
  VoiceAlertService._();

  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;

  static Future<void> _init() async {
    if (_initialized) return;
    await _tts.setLanguage('en-IN');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(0.9);
    await _tts.setPitch(1.0);
    _initialized = true;
  }

  /// Speak text aloud through the device speaker.
  static Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _init();
    await _tts.speak(text);
  }

  /// Stop any ongoing speech.
  static Future<void> stop() async {
    await _tts.stop();
  }
}
