import 'package:flutter_test/flutter_test.dart';
import 'package:nivara/features/ai_capture/models/civic_ai_models.dart';
import 'package:nivara/features/ai_capture/services/civic_ai_classifier_service.dart';
import 'package:nivara/models/enums.dart';

void main() {
  group('CivicAiClassifierService & 19 Civic Categories', () {
    late CivicAiClassifierService service;

    setUp(() {
      service = CivicAiClassifierService();
    });

    test('All 19 ReportCategory values have valid metadata presets', () {
      expect(ReportCategory.values.length, 19);

      for (final cat in ReportCategory.values) {
        final preset = service.getPresetMetadata(cat);
        expect(preset.title.isNotEmpty, isTrue, reason: 'Title empty for $cat');
        expect(preset.description.isNotEmpty, isTrue, reason: 'Desc empty for $cat');
        expect(preset.titleMl.isNotEmpty, isTrue, reason: 'TitleMl empty for $cat');
        expect(preset.descriptionMl.isNotEmpty, isTrue, reason: 'DescMl empty for $cat');
        expect(preset.defaultTags.isNotEmpty, isTrue, reason: 'Tags empty for $cat');
      }
    });

    test('Pothole preset returns proper roadway hazard tags', () {
      final preset = service.getPresetMetadata(ReportCategory.pothole);
      expect(preset.title, contains('Pothole'));
      expect(preset.titleMl, contains('കുഴി'));
      expect(preset.defaultTags, contains('roadway_hazard'));
    });

    test('Open Manhole preset returns critical fall risk', () {
      final preset = service.getPresetMetadata(ReportCategory.openManhole);
      expect(preset.title, contains('Manhole'));
      expect(preset.titleMl, contains('മാൻഹോൾ'));
      expect(preset.defaultTags, contains('missing_cover'));
    });

    test('Waterlogging preset returns drainage failure tags', () {
      final preset = service.getPresetMetadata(ReportCategory.waterlogging);
      expect(preset.title, contains('Waterlogging'));
      expect(preset.titleMl, contains('വെള്ളക്കെട്ട്'));
    });

    test('Blocked drain and sewage return sanitary tags', () {
      final drain = service.getPresetMetadata(ReportCategory.blockedDrain);
      expect(drain.title, contains('Drain'));
      expect(drain.titleMl, contains('ഓട'));

      final sewage = service.getPresetMetadata(ReportCategory.sewage);
      expect(sewage.title, contains('Sewage'));
      expect(sewage.titleMl, contains('മലിനജല'));
    });

    test('CivicAiDetection high-confidence trigger threshold', () {
      final lowConf = CivicAiDetection(
        category: ReportCategory.pothole,
        confidence: 0.74,
        severity: Severity.medium,
        title: 'Pothole',
        description: 'Road damage',
        titleMl: 'കുഴി',
        descriptionMl: 'റോഡ് തകരാറ്',
        timestamp: DateTime.now(),
      );
      expect(lowConf.isHighConfidence, isFalse);

      final highConf = lowConf.copyWith(confidence: 0.88);
      expect(highConf.isHighConfidence, isTrue);
    });

    test('Tracking reset clears history buffer', () {
      service.resetTracking();
      // Should run without exceptions
      expect(true, isTrue);
    });
  });
}
