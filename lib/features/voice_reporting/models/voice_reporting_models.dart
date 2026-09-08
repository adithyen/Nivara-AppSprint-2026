import '../../../models/enums.dart';

/// Target domain for the voice report.
enum VoiceReportMode {
  civic('CIVIC', 'Civic Hazard'),
  lostFound('LOST_FOUND', 'Lost & Found'),
  community('COMMUNITY', 'Community Post');

  final String wire;
  final String label;
  const VoiceReportMode(this.wire, this.label);
}

/// Operational state of the speech recognition pipeline.
enum VoiceState {
  idle,
  listening,
  processing,
  completed,
  error,
}

/// Language modes supported by Nivara's speech engine.
enum VoiceLanguage {
  auto('auto', 'Auto (Device)', '🌐'),
  en('en_IN', 'English', '🇬🇧'),
  ml('ml_IN', 'മലയാളം', '🇮🇳'),
  hi('hi_IN', 'हिंदी', '🇮🇳');

  final String localeId;
  final String label;
  final String flag;
  const VoiceLanguage(this.localeId, this.label, this.flag);

  static VoiceLanguage fromCode(String code) {
    if (code.startsWith('ml')) return VoiceLanguage.ml;
    if (code.startsWith('hi')) return VoiceLanguage.hi;
    if (code.startsWith('en')) return VoiceLanguage.en;
    return VoiceLanguage.auto;
  }
}

/// Structured payload extracted from natural voice dictation.
class VoiceReportPayload {
  final VoiceReportMode mode;
  final ReportCategory? civicCategory;
  final Severity severity;
  final LFItemType lfItemType;
  final LFCategory? lfCategory;
  final CommunityPostType communityType;
  final String title;
  final String description;
  final String? extractedLandmark;
  final String? contactInfo;
  final List<String> tags;
  final List<String> pollOptions;
  final String rawTranscript;
  final double confidence;
  final DateTime timestamp;

  const VoiceReportPayload({
    required this.mode,
    this.civicCategory,
    this.severity = Severity.medium,
    this.lfItemType = LFItemType.lost,
    this.lfCategory,
    this.communityType = CommunityPostType.general,
    required this.title,
    required this.description,
    this.extractedLandmark,
    this.contactInfo,
    this.tags = const [],
    this.pollOptions = const [],
    required this.rawTranscript,
    this.confidence = 0.90,
    required this.timestamp,
  });

  VoiceReportPayload copyWith({
    VoiceReportMode? mode,
    ReportCategory? civicCategory,
    Severity? severity,
    LFItemType? lfItemType,
    LFCategory? lfCategory,
    CommunityPostType? communityType,
    String? title,
    String? description,
    String? extractedLandmark,
    String? contactInfo,
    List<String>? tags,
    List<String>? pollOptions,
    String? rawTranscript,
    double? confidence,
    DateTime? timestamp,
  }) {
    return VoiceReportPayload(
      mode: mode ?? this.mode,
      civicCategory: civicCategory ?? this.civicCategory,
      severity: severity ?? this.severity,
      lfItemType: lfItemType ?? this.lfItemType,
      lfCategory: lfCategory ?? this.lfCategory,
      communityType: communityType ?? this.communityType,
      title: title ?? this.title,
      description: description ?? this.description,
      extractedLandmark: extractedLandmark ?? this.extractedLandmark,
      contactInfo: contactInfo ?? this.contactInfo,
      tags: tags ?? this.tags,
      pollOptions: pollOptions ?? this.pollOptions,
      rawTranscript: rawTranscript ?? this.rawTranscript,
      confidence: confidence ?? this.confidence,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toCivicFormExtra() {
    return {
      'initialTitle': title,
      'initialDesc': description,
      'initialCategory': civicCategory,
      'initialSeverity': severity,
      'initialTags': tags,
      'landmark': extractedLandmark,
    };
  }

  Map<String, dynamic> toLFFormExtra() {
    return {
      'initialTitle': title,
      'initialDesc': description,
      'initialCategory': lfCategory,
      'initialItemType': lfItemType,
      'landmark': extractedLandmark,
    };
  }

  Map<String, dynamic> toCommunityComposeExtra() {
    return {
      'initialTitle': title,
      'initialBody': description,
      'initialPostType': communityType,
      'landmark': extractedLandmark,
    };
  }
}
