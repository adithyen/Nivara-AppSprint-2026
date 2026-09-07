import 'package:flutter_test/flutter_test.dart';
import 'package:nivara/features/voice_reporting/models/voice_reporting_models.dart';
import 'package:nivara/features/voice_reporting/services/voice_intent_parser_service.dart';
import 'package:nivara/models/enums.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VoiceIntentParserService parser;

  setUp(() {
    parser = VoiceIntentParserService();
  });

  group('VoiceIntentParserService - Civic Mode (19 Categories & Multilingual)', () {
    test('English: Detects pothole and landmark location', () async {
      const transcript =
          'There is a massive pothole on MG Road near the metro station that is damaging vehicles.';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.civic,
        language: VoiceLanguage.en,
      );

      expect(payload.civicCategory, ReportCategory.pothole);
      expect(payload.title, contains('Pothole'));
      expect(payload.extractedLandmark, isNotNull);
      expect(
        payload.extractedLandmark!.toLowerCase(),
        anyOf(contains('road'), contains('station')),
      );
    });

    test('Malayalam: Detects open manhole and high severity', () async {
      const transcript =
          'ഇവിടെ റോഡിൽ ഒരു വലിയ മാൻഹോൾ അടപ്പില്ലാതെ തുറന്നുകിടക്കുന്നു ഉടൻ പരിഹരിക്കണം';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.civic,
        language: VoiceLanguage.ml,
      );

      expect(payload.civicCategory, ReportCategory.openManhole);
      expect(payload.title, anyOf(contains('Manhole'), contains('മാൻഹോൾ')));
      expect(
        payload.severity == Severity.high || payload.severity == Severity.emergency,
        isTrue,
      );
    });

    test('Malayalam: Detects waterlogging', () async {
      const transcript = 'റോഡിൽ കനത്ത മഴ കാരണം വലിയ വെള്ളക്കെട്ട് ഉണ്ടായിട്ടുണ്ട്';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.civic,
        language: VoiceLanguage.ml,
      );

      expect(payload.civicCategory, ReportCategory.waterlogging);
    });

    test('Hindi: Detects garbage dump / trash', () async {
      const transcript = 'यहाँ मेन रोड पर बहुत सारा कचरा जमा हुआ है और बहुत बदबू आ रही है';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.civic,
        language: VoiceLanguage.hi,
      );

      expect(payload.civicCategory, ReportCategory.garbage);
      expect(payload.title, contains('Garbage'));
    });

    test('Hindi: Detects street light outage', () async {
      const transcript = 'गली की स्ट्रीट लाइट खराब है रात को पूरा अंधेरा रहता है';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.civic,
        language: VoiceLanguage.hi,
      );

      expect(payload.civicCategory, ReportCategory.streetLight);
    });

    test('English: Detects fallen tree blocking road', () async {
      const transcript =
          'A huge fallen tree is blocking both lanes near the civil station junction.';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.civic,
        language: VoiceLanguage.en,
      );

      expect(payload.civicCategory, ReportCategory.fallenTree);
    });

    test('English: Detects water pipeline leakage', () async {
      const transcript =
          'The main municipal water pipe is burst and water is leaking heavily across the road';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.civic,
        language: VoiceLanguage.en,
      );

      expect(payload.civicCategory, ReportCategory.pipeLeak);
    });

    test('English: Detects stray animals / dog menace', () async {
      const transcript =
          'Pack of aggressive stray dogs chasing pedestrians and children in the park area';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.civic,
        language: VoiceLanguage.en,
      );

      expect(payload.civicCategory, ReportCategory.strayAnimals);
    });
  });

  group('VoiceIntentParserService - Lost & Found Mode', () {
    test('English: Lost wallet with identity cards', () async {
      const transcript =
          'I lost my brown leather wallet containing my driving license and credit cards near city center';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.lostFound,
        language: VoiceLanguage.en,
      );

      expect(payload.lfItemType, LFItemType.lost);
      expect(payload.lfCategory, LFCategory.wallet);
      expect(payload.title.toLowerCase(), contains('lost'));
      expect(payload.title.toLowerCase(), contains('wallet'));
    });

    test('English: Found smartphone', () async {
      const transcript =
          'Found a black iPhone 14 with a clear case lying on the bench at central park';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.lostFound,
        language: VoiceLanguage.en,
      );

      expect(payload.lfItemType, LFItemType.found);
      expect(payload.lfCategory, LFCategory.mobilePhone);
      expect(payload.title.toLowerCase(), contains('found'));
    });

    test('Malayalam: Lost vehicle keys', () async {
      const transcript =
          'എന്റെ ബൈക്കിന്റെ താക്കോൽ ബസ് സ്റ്റാൻഡ് പരിസരത്ത് വെച്ച് നഷ്ടപ്പെട്ടു';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.lostFound,
        language: VoiceLanguage.ml,
      );

      expect(payload.lfItemType, LFItemType.lost);
      expect(payload.lfCategory, LFCategory.keys);
    });

    test('Hindi: Found bag', () async {
      const transcript = 'मुझे बस स्टॉप पर एक लाल रंग का बैग मिला है';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.lostFound,
        language: VoiceLanguage.hi,
      );

      expect(payload.lfItemType, LFItemType.found);
      expect(payload.lfCategory, LFCategory.bag);
    });
  });

  group('VoiceIntentParserService - Community Mode', () {
    test('English: Detects poll intention', () async {
      const transcript =
          'Poll: Should our neighborhood association install solar lights in the park? Vote yes or no';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.community,
        language: VoiceLanguage.en,
      );

      expect(payload.communityType, CommunityPostType.poll);
    });

    test('English: Detects announcement intention', () async {
      const transcript =
          'Important public announcement: Power supply will be interrupted tomorrow from 9am to 2pm for maintenance';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.community,
        language: VoiceLanguage.en,
      );

      expect(payload.communityType, CommunityPostType.announcement);
    });

    test('English: Detects job / hiring post', () async {
      const transcript =
          'Hiring urgently: Need an experienced plumber for apartment pipe repair work';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.community,
        language: VoiceLanguage.en,
      );

      expect(payload.communityType, CommunityPostType.job);
    });

    test('English: Default general post', () async {
      const transcript =
          'Had a wonderful time meeting the neighbors at our community garden harvest event today';
      final payload = await parser.parseTranscript(
        transcript,
        forcedMode: VoiceReportMode.community,
        language: VoiceLanguage.en,
      );

      expect(payload.communityType, CommunityPostType.general);
    });
  });

  group('VoiceReportPayload Navigation & Extras Export', () {
    test('Exports valid Civic extra payload map', () {
      final payload = VoiceReportPayload(
        mode: VoiceReportMode.civic,
        rawTranscript: 'Big pothole near bypass',
        title: 'Pothole on Main St',
        description: 'Deep road depression',
        civicCategory: ReportCategory.pothole,
        severity: Severity.high,
        extractedLandmark: 'Near bypass',
        tags: const ['pothole', 'road'],
        timestamp: DateTime.now(),
      );

      final extra = payload.toCivicFormExtra();
      expect(extra['initialTitle'], 'Pothole on Main St');
      expect(extra['initialDesc'], 'Deep road depression');
      expect(extra['initialCategory'], ReportCategory.pothole);
      expect(extra['initialSeverity'], Severity.high);
      expect(extra['initialTags'], contains('pothole'));
    });

    test('Exports valid Lost & Found extra payload map', () {
      final payload = VoiceReportPayload(
        mode: VoiceReportMode.lostFound,
        rawTranscript: 'Lost black wallet',
        title: 'Lost Wallet',
        description: 'Black leather wallet',
        lfItemType: LFItemType.lost,
        lfCategory: LFCategory.wallet,
        timestamp: DateTime.now(),
      );

      final extra = payload.toLFFormExtra();
      expect(extra['initialTitle'], 'Lost Wallet');
      expect(extra['initialDesc'], 'Black leather wallet');
      expect(extra['initialCategory'], LFCategory.wallet);
    });

    test('Exports valid Community post extra payload map', () {
      final payload = VoiceReportPayload(
        mode: VoiceReportMode.community,
        rawTranscript: 'Notice about park cleanup',
        title: 'Park Cleanup Notice',
        description: 'Community cleanup on Saturday',
        communityType: CommunityPostType.announcement,
        timestamp: DateTime.now(),
      );

      final extra = payload.toCommunityComposeExtra();
      expect(extra['initialTitle'], 'Park Cleanup Notice');
      expect(extra['initialBody'], 'Community cleanup on Saturday');
      expect(extra['initialPostType'], CommunityPostType.announcement);
    });
  });
}
