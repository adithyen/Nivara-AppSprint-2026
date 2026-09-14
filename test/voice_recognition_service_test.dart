import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivara/features/voice_reporting/models/voice_reporting_models.dart';
import 'package:nivara/features/voice_reporting/services/voice_recognition_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VoiceRecognitionService service;

  setUp(() {
    service = VoiceRecognitionService();
  });

  tearDown(() {
    service.dispose();
  });

  group('VoiceRecognitionService Lifecycle & Buffer Reset Tests', () {
    test('Initial state is idle and not listening', () {
      expect(service.state, VoiceState.idle);
      expect(service.isListening, isFalse);
      expect(service.accumulatedText, isEmpty);
    });

    test('updateBaseText correctly updates accumulated text and clears session', () {
      service.updateBaseText('Pothole near metro');
      expect(service.accumulatedText, 'Pothole near metro');
    });

    test('clearBuffer clears all buffers completely', () async {
      service.updateBaseText('Some previous text');
      expect(service.accumulatedText, 'Some previous text');

      await service.clearBuffer(restartIfListening: false);
      expect(service.accumulatedText, isEmpty);
    });

    test('cancelSync halts listening, resets buffer and state to idle', () {
      service.updateBaseText('Old spoken words');
      service.cancelSync();

      expect(service.isListening, isFalse);
      expect(service.state, VoiceState.idle);
      expect(service.accumulatedText, isEmpty);
    });

    test('didChangeAppLifecycleState(paused) halts listening and prevents leaks', () {
      service.updateBaseText('Active speech text');
      service.didChangeAppLifecycleState(AppLifecycleState.paused);

      expect(service.isListening, isFalse);
      expect(service.state, VoiceState.idle);
      expect(service.accumulatedText, isEmpty);
    });

    test('didChangeAppLifecycleState(inactive) halts listening and prevents leaks', () {
      service.updateBaseText('Active speech text');
      service.didChangeAppLifecycleState(AppLifecycleState.inactive);

      expect(service.isListening, isFalse);
      expect(service.state, VoiceState.idle);
      expect(service.accumulatedText, isEmpty);
    });

    test('didChangeAppLifecycleState(hidden) halts listening and prevents leaks', () {
      service.updateBaseText('Active speech text');
      service.didChangeAppLifecycleState(AppLifecycleState.hidden);

      expect(service.isListening, isFalse);
      expect(service.state, VoiceState.idle);
      expect(service.accumulatedText, isEmpty);
    });
  });
}
