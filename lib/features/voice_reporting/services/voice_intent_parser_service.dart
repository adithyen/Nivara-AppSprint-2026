import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../models/enums.dart';
import '../models/voice_reporting_models.dart';

final voiceIntentParserServiceProvider = Provider<VoiceIntentParserService>((ref) {
  return VoiceIntentParserService();
});

/// Intelligent semantic parser that translates spoken natural language into
/// structured payloads across Civic, Lost & Found, and Community domains.
class VoiceIntentParserService {
  /// Parses natural language text into a structured VoiceReportPayload.
  /// Runs fast offline rule-based extraction, and optionally augments with
  /// Gemini Flash when available online.
  Future<VoiceReportPayload> parseTranscript(
    String transcript, {
    VoiceReportMode? forcedMode,
    CommunityPostType? forcedCommunityType,
    VoiceLanguage language = VoiceLanguage.auto,
    bool enableAiRefinement = false,
  }) async {
    final cleanText = transcript.trim();
    if (cleanText.isEmpty) {
      return VoiceReportPayload(
        mode: forcedMode ?? VoiceReportMode.civic,
        communityType: forcedCommunityType ?? CommunityPostType.general,
        title: 'Spoken Complaint',
        description: 'No speech content recorded.',
        rawTranscript: transcript,
        timestamp: DateTime.now(),
      );
    }

    // 1. Determine target mode (Civic, Lost & Found, or Community)
    final mode = forcedMode ?? _detectMode(cleanText);

    // 2. Fast offline semantic slot extraction (zero latency)
    VoiceReportPayload payload;
    switch (mode) {
      case VoiceReportMode.civic:
        payload = _extractCivicSlots(cleanText, language);
        break;
      case VoiceReportMode.lostFound:
        payload = _extractLostFoundSlots(cleanText, language);
        break;
      case VoiceReportMode.community:
        payload = _extractCommunitySlots(cleanText, language, forcedType: forcedCommunityType);
        break;
    }

    // 3. Optional Gemini Flash semantic refinement only when enabled (final result)
    if (enableAiRefinement) {
      final geminiKey = dotenv.isInitialized ? dotenv.env['GEMINI_API_KEY']?.trim() : null;
      if (geminiKey != null && geminiKey.isNotEmpty) {
        try {
          final refined = await _refineWithGemini(cleanText, mode, payload, geminiKey);
          if (refined != null) {
            payload = refined;
          }
        } catch (e) {
          debugPrint('[VoiceIntentParserService] Gemini refinement skipped: $e');
        }
      }
    }

    return payload;
  }

  /// Automatically classifies which mode the user is speaking about.
  VoiceReportMode _detectMode(String text) {
    final lower = text.toLowerCase();

    // Lost & Found signatures
    final lfMatches = [
      'lost', 'missing', 'found', 'picked up', 'wallet', 'keys', 'purse',
      'backpack', 'handbag', 'aadhaar', 'id card', 'pet dog', 'cat',
      'നഷ്ടപ്പെട്ടു', 'നഷ്ടമായി', 'കളഞ്ഞുപോയി', 'കണ്ടെത്തി', 'കിട്ടി', 'ലഭിച്ചു',
      'വാലറ്റ്', 'താക്കോൽ', 'പഴ്സ്', 'ആധാർ', 'खो गया', 'खोई', 'मिला', 'पाया', 'बटुआ'
    ];
    if (lfMatches.any((kw) => lower.contains(kw))) {
      return VoiceReportMode.lostFound;
    }

    // Community post signatures
    final communityMatches = [
      'poll', 'vote', 'survey', 'announcement', 'notice', 'meeting', 'event',
      'cleanliness drive', 'volunteers', 'job', 'hiring', 'plumber needed',
      'പോൾ', 'വോട്ട്', 'അറിയിപ്പ്', 'യോഗം', 'കൂട്ടായ്മ', 'ക്ലീനിംഗ്',
      'ജോലി', 'പോസ്റ്റ്', 'घोषणा', 'मतदान', 'सफाई अभियान', 'सूचना'
    ];
    if (communityMatches.any((kw) => lower.contains(kw))) {
      return VoiceReportMode.community;
    }

    // Default to Civic Hazard
    return VoiceReportMode.civic;
  }

  /// Extracts Civic issue category, severity, landmark, and title.
  VoiceReportPayload _extractCivicSlots(String text, VoiceLanguage lang) {
    final lower = text.toLowerCase();
    ReportCategory category = ReportCategory.pothole;
    Severity severity = Severity.medium;
    final List<String> tags = [];

    // Map to 19 categories
    if (_containsAny(lower, ['pothole', 'crater', 'bitumen', 'road broken', 'കുഴി', 'റോഡിലെ കുഴി', 'ടാർ', 'गड्ढा'])) {
      category = ReportCategory.pothole;
      tags.addAll(['roadway_hazard', 'pothole']);
    } else if (_containsAny(lower, ['manhole', 'open hole', 'chamber', 'drain cover', 'മാൻഹോൾ', 'തുറന്ന മാൻഹോൾ', 'मैनहोल'])) {
      category = ReportCategory.openManhole;
      severity = Severity.emergency;
      tags.addAll(['critical_hazard', 'open_manhole']);
    } else if (_containsAny(lower, ['waterlogging', 'water logging', 'water logged', 'flood', 'puddle', 'rainwater', 'വെള്ളക്കെട്ട്', 'വെള്ളം കെട്ടി', 'जलभराव'])) {
      category = ReportCategory.waterlogging;
      tags.addAll(['stormwater', 'waterlogging']);
    } else if (_containsAny(lower, ['garbage', 'trash', 'waste', 'dump', 'litter', 'plastic waste', 'മാലിന്യം', 'ചപ്പുചവറുകൾ', 'കച്ചറ', 'कचरा'])) {
      category = ReportCategory.garbage;
      tags.addAll(['solid_waste', 'sanitation']);
    } else if (_containsAny(lower, ['drain', 'gutter', 'culvert', 'choked drain', 'blocked drain', 'ഓട', 'തടസ്സപ്പെട്ട ഓട', 'ഓവുചാൽ', 'नाली'])) {
      category = ReportCategory.blockedDrain;
      tags.addAll(['drainage_issue', 'blocked_drain']);
    } else if (_containsAny(lower, ['sewage', 'foul water', 'smell', 'blackwater', 'stink', 'മലിനജലം', 'സീവേജ്', 'ദുർഗന്ധം', 'सीवेज'])) {
      category = ReportCategory.sewage;
      severity = Severity.high;
      tags.addAll(['public_health', 'sewage_leak']);
    } else if (_containsAny(lower, ['streetlight', 'street light', 'lamp', 'dark road', 'bulb broken', 'തെരുവ് വിളക്ക്', 'സ്ട്രീറ്റ് ലൈറ്റ്', 'ഇരുട്ട്', 'स्ट्रीट लाइट'])) {
      category = ReportCategory.streetLight;
      tags.addAll(['lighting', 'streetlight']);
    } else if (_containsAny(lower, ['pole', 'electric post', 'tilted post', 'bent pole', 'പോസ്റ്റ്', 'ഇലക്ട്രിക് പോസ്റ്റ്', 'പോൾ ചരിഞ്ഞു', 'खंभा'])) {
      category = ReportCategory.damagedPole;
      severity = Severity.high;
      tags.addAll(['damaged_pole', 'utility_hazard']);
    } else if (_containsAny(lower, ['live wire', 'wire', 'cable', 'dangling', 'sparking', 'electric wire', 'വൈദ്യുതി കമ്പി', 'വയർ', 'ഷോക്ക്', 'तार'])) {
      category = ReportCategory.powerIssue;
      severity = Severity.emergency;
      tags.addAll(['electrocution_risk', 'live_wire']);
    } else if (_containsAny(lower, ['pipe', 'water pipe', 'pipeline', 'leak', 'pipe burst', 'water leak', 'drinking water leak', 'പൈപ്പ്', 'പൈപ്പ് പൊട്ടി', 'പൈപ്പ് ചോർച്ച', 'വെള്ളം പാഴാകുന്നു', 'पाइप रिसाव', 'पाइप'])) {
      category = ReportCategory.pipeLeak;
      tags.addAll(['water_loss', 'pipe_leak']);
    } else if (_containsAny(lower, ['water supply', 'no water', 'tap broken', 'public tap', 'കുടിവെള്ളം', 'വെള്ളം ലഭ്യമല്ല', 'പൈപ്പിൽ വെള്ളമില്ല', 'पानी नहीं'])) {
      category = ReportCategory.waterSupply;
      tags.addAll(['water_outage', 'public_tap']);
    } else if (_containsAny(lower, ['tree', 'fallen tree', 'branch', 'tree fell', 'മരം വീണു', 'മരം കടപുഴകി', 'ചില്ല ഒടിഞ്ഞു', 'पेड़ गिरा'])) {
      category = ReportCategory.fallenTree;
      severity = Severity.high;
      tags.addAll(['traffic_block', 'fallen_tree']);
    } else if (_containsAny(lower, ['footpath', 'broken footpath', 'sidewalk', 'paver', 'walking track', 'നടപ്പാത', 'തകർന്ന നടപ്പാത', 'ടൈലുകൾ പൊട്ടി', 'फुटपाथ'])) {
      category = ReportCategory.brokenFootpath;
      tags.addAll(['pedestrian_hazard', 'footpath']);
    } else if (_containsAny(lower, ['encroachment', 'illegal stall', 'pavement occupied', 'shed', 'കയ്യേറ്റം', 'നടപ്പാത കയ്യേറ്റം', 'തട്ടുകട', 'अतिक्रमण'])) {
      category = ReportCategory.encroachment;
      tags.addAll(['right_of_way', 'encroachment']);
    } else if (_containsAny(lower, ['bus shelter', 'park bench', 'railing', 'broken property', 'പൊതുമുതൽ', 'ബസ് സ്റ്റോപ്പ് തകർത്തു', 'കൈവരി', 'संपत्ति क्षति'])) {
      category = ReportCategory.brokenProperty;
      tags.addAll(['vandalism', 'public_property']);
    } else if (_containsAny(lower, ['stray animal', 'stray dog', 'cattle', 'cow on road', 'തെരുവ് നായ', 'പശു', 'മൃഗങ്ങൾ', 'തെരുവ് മൃഗങ്ങൾ', 'आवारा कुत्ते'])) {
      category = ReportCategory.strayAnimals;
      tags.addAll(['animal_hazard', 'traffic_safety']);
    } else if (_containsAny(lower, ['road sign', 'signboard', 'sign board', 'traffic board', 'ട്രാഫിക് ബോർഡ്', 'സൈൻ ബോർഡ്', 'ബോർഡ് തകർന്നു', 'संकेत'])) {
      category = ReportCategory.roadSign;
      tags.addAll(['traffic_safety', 'road_sign']);
    } else if (_containsAny(lower, ['noise', 'loudspeaker', 'generator noise', 'sound pollution', 'ശബ്ദം', 'ശബ്ദ മലിനീകരണം', 'മൈക്ക്', 'ध्वनि'])) {
      category = ReportCategory.noise;
      tags.addAll(['noise_pollution', 'decibel_violation']);
    } else {
      category = ReportCategory.pothole;
      tags.addAll(['civic_complaint']);
    }

    // Severity assessment
    if (_containsAny(lower, ['huge', 'severe', 'dangerous', 'danger', 'emergency', 'critical', 'deep', 'sparking', 'അപകടം', 'അടിയന്തിരം', 'കടുത്ത', 'വലിയ കുഴി', 'गंभीर', 'खतरनाक', 'आपातकालीन'])) {
      severity = (category == ReportCategory.openManhole || category == ReportCategory.powerIssue)
          ? Severity.emergency
          : Severity.high;
    } else if (_containsAny(lower, ['small', 'minor', 'slight', 'കുറഞ്ഞ', 'ചെറിയ', 'मामूली', 'हल्का'])) {
      severity = Severity.low;
    }

    final landmark = _extractLandmark(text);
    final title = _generateCivicTitle(category, severity, landmark, lang);

    return VoiceReportPayload(
      mode: VoiceReportMode.civic,
      civicCategory: category,
      severity: severity,
      title: title,
      description: text,
      extractedLandmark: landmark,
      tags: tags,
      rawTranscript: text,
      timestamp: DateTime.now(),
    );
  }

  /// Extracts Lost & Found item details, type (lost vs found), and category.
  VoiceReportPayload _extractLostFoundSlots(String text, VoiceLanguage lang) {
    final lower = text.toLowerCase();

    // Type detection: Lost vs Found
    LFItemType itemType = LFItemType.lost;
    if (_containsAny(lower, ['found', 'picked up', 'saw', 'got', 'spotted', 'കണ്ടെത്തി', 'കിട്ടി', 'ലഭിച്ചു', 'കണ്ടു', 'मिला', 'पाया'])) {
      itemType = LFItemType.found;
    }

    // Category detection
    LFCategory category = LFCategory.other;
    final List<String> tags = [];

    if (_containsAny(lower, ['wallet', 'purse', 'money bag', 'വാലറ്റ്', 'പഴ്സ്', 'പണപ്പൈ', 'बटुआ'])) {
      category = LFCategory.wallet;
      tags.addAll(['wallet', 'personal_item']);
    } else if (_containsAny(lower, ['mobile', 'phone', 'smartphone', 'iphone', 'android', 'ഫോൺ', 'മൊബൈൽ', 'സ്മാർട്ട്ഫോൺ', 'फोन', 'मोबाइल'])) {
      category = LFCategory.mobilePhone;
      tags.addAll(['electronics', 'phone']);
    } else if (_containsAny(lower, ['key', 'keys', 'bike key', 'car key', 'താക്കോൽ', 'ബൈക്ക് കീ', 'ചാവി', 'चाबी'])) {
      category = LFCategory.keys;
      tags.addAll(['keys', 'access']);
    } else if (_containsAny(lower, ['bag', 'backpack', 'handbag', 'suitcase', 'ബാഗ്', 'ഹാൻഡ് ബാഗ്', 'ഷോൾഡർ ബാഗ്', 'बैग', 'बस्ता'])) {
      category = LFCategory.bag;
      tags.addAll(['bag', 'luggage']);
    } else if (_containsAny(lower, ['aadhaar', 'aadhar', 'id card', 'college id', 'voter id', 'license', 'ആധാർ', 'ഐഡി കാർഡ്', 'ലൈസൻസ്', 'आधार', 'पहचान पत्र'])) {
      category = LFCategory.aadhaar;
      tags.addAll(['identity', 'document']);
    } else if (_containsAny(lower, ['pet', 'dog', 'puppy', 'cat', 'kitten', 'നായ', 'പൂച്ച', 'നായക്കുട്ടി', 'കുട്ടപ്പൻ', 'കുറ്റൻ', 'कुत्ता', 'बिल्ली'])) {
      category = LFCategory.pet;
      tags.addAll(['pet', 'animal']);
    } else if (_containsAny(lower, ['gold', 'chain', 'ring', 'jewellery', 'necklace', 'മാല', 'മോതിരം', 'സ്വർണ്ണം', 'ചെയിൻ', 'गहने', 'अंगूठी'])) {
      category = LFCategory.jewellery;
      tags.addAll(['valuable', 'jewellery']);
    } else if (_containsAny(lower, ['bike', 'scooter', 'helmet', 'vehicle', 'ബൈക്ക്', 'സ്കൂട്ടർ', 'ഹെൽമെറ്റ്', 'वाहन', 'बाइक'])) {
      category = LFCategory.vehicle;
      tags.addAll(['vehicle', 'transport']);
    }

    final landmark = _extractLandmark(text);
    final title = '${itemType == LFItemType.lost ? "Lost" : "Found"}: ${category.label}';

    return VoiceReportPayload(
      mode: VoiceReportMode.lostFound,
      lfItemType: itemType,
      lfCategory: category,
      title: title,
      description: text,
      extractedLandmark: landmark,
      tags: tags,
      rawTranscript: text,
      timestamp: DateTime.now(),
    );
  }

  /// Extracts Community post type, title, and body.
  VoiceReportPayload _extractCommunitySlots(
    String text,
    VoiceLanguage lang, {
    CommunityPostType? forcedType,
  }) {
    final lower = text.toLowerCase();
    CommunityPostType type = forcedType ?? CommunityPostType.general;
    final List<String> tags = [];

    if (forcedType == null) {
      if (_containsAny(lower, [
        'poll', 'vote', 'survey', 'opinion', 'voting',
        'വോട്ട്', 'പോൾ', 'അഭിപ്രായം', 'വോട്ടെടുപ്പ്',
        'मतदान', 'राय', 'वोट', 'पोल'
      ])) {
        type = CommunityPostType.poll;
      } else if (_containsAny(lower, [
        'announcement', 'notice', 'alert', 'information', 'meeting', 'event',
        'cleanliness drive', 'circular', 'warning', 'news',
        'അറിയിപ്പ്', 'ശ്രദ്ധിക്കുക', 'വിവരം', 'യോഗം', 'കൂട്ടായ്മ', 'ക്ലീനിംഗ്', 'പരിപാടി',
        'घोषणा', 'सूचना', 'बैठक', 'कार्यक्रम', 'सफाई अभियान'
      ])) {
        type = CommunityPostType.announcement;
      } else if (_containsAny(lower, [
        'job', 'hiring', 'work', 'plumber', 'electrician', 'mechanic', 'maid',
        'driver', 'carpenter', 'painter', 'cook', 'service needed', 'help needed', 'vacancy',
        'ജോലി', 'പ്ലംബർ', 'ഇലക്ട്രീഷ്യൻ', 'ഡ്രൈവർ', 'ആവശ്യമുണ്ട്', 'സഹായം', 'തൊഴിൽ',
        'नौकरी', 'काम', 'इलेक्ट्रीशियन', 'प्लंबर', 'मदद', 'चालक'
      ])) {
        type = CommunityPostType.job;
      } else {
        type = CommunityPostType.general;
      }
    }

    switch (type) {
      case CommunityPostType.poll:
        tags.addAll(['poll', 'community_voice']);
        break;
      case CommunityPostType.announcement:
        tags.addAll(['announcement', 'official', 'alert']);
        break;
      case CommunityPostType.job:
        tags.addAll(['jobs', 'services', 'neighbourhood_help']);
        break;
      case CommunityPostType.general:
        tags.addAll(['neighbourhood', 'discussion']);
        break;
    }

    final landmark = _extractLandmark(text);
    String title = text.length > 60 ? '${text.substring(0, 57)}...' : text;
    if (type == CommunityPostType.announcement && !title.toLowerCase().startsWith('announcement:')) {
      title = 'Announcement: $title';
    } else if (type == CommunityPostType.poll && !title.toLowerCase().startsWith('poll:')) {
      title = 'Poll: $title';
    } else if (type == CommunityPostType.job && !title.toLowerCase().startsWith('job:')) {
      title = 'Job/Service: $title';
    }

    return VoiceReportPayload(
      mode: VoiceReportMode.community,
      communityType: type,
      title: title,
      description: text,
      extractedLandmark: landmark,
      tags: tags,
      rawTranscript: text,
      timestamp: DateTime.now(),
    );
  }

  /// Helper to extract landmarks / street locations mentioned in speech.
  String? _extractLandmark(String text) {
    final patterns = [
      RegExp(r'(?:near|at|around|opposite|beside)\s+([A-Za-z0-9\s]+?)(?:junction|bus stand|station|road|street|nagar|colony|market|temple|church|hospital|\.|$)', caseSensitive: false),
      RegExp(r'([A-Za-z0-9\s]+?)\s+(?:junction|bus stand|station|road|street|nagar|colony)', caseSensitive: false),
      RegExp(r'([^\s]+)\s+(?:ജംഗ്ഷൻ|ബസ് സ്റ്റാൻഡ്|റോഡിൽ|സ്റ്റോപ്പ്|പാലം)', caseSensitive: false),
      RegExp(r'([^\s]+)\s+(?:चौक|स्टेशन|बस स्टैंड|रोड|सड़क)', caseSensitive: false),
    ];

    for (final p in patterns) {
      final match = p.firstMatch(text);
      if (match != null) {
        final captured = match.group(0)?.trim();
        if (captured != null && captured.length > 2 && captured.length < 50) {
          return captured;
        }
      }
    }
    return null;
  }

  String _generateCivicTitle(ReportCategory cat, Severity sev, String? landmark, VoiceLanguage lang) {
    final prefix = sev == Severity.emergency ? 'CRITICAL: ' : (sev == Severity.high ? 'Severe ' : '');
    final place = landmark != null ? ' near $landmark' : '';

    if (lang == VoiceLanguage.ml) {
      return '${cat.localizedName('ml')}$place';
    } else if (lang == VoiceLanguage.hi) {
      return '${cat.localizedName('hi')}$place';
    }
    return '$prefix${cat.label}$place';
  }

  bool _containsAny(String text, List<String> keywords) {
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  /// Calls Google Gemini Flash REST endpoint to refine the structured payload with deep multimodal understanding.
  Future<VoiceReportPayload?> _refineWithGemini(
    String transcript,
    VoiceReportMode mode,
    VoiceReportPayload fallback,
    String apiKey,
  ) async {
    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey',
      );

      final prompt = '''
You are Nivara's civic voice intelligence assistant.
Analyze this spoken transcript from a citizen (may be in English, Malayalam, or Hindi):
"$transcript"

The report mode is: ${mode.name}

Extract and return strictly raw JSON (no markdown formatting, no backticks):
{
  "mode": "CIVIC" | "LOST_FOUND" | "COMMUNITY",
  "civic_category": "POTHOLE" | "OPEN_MANHOLE" | "WATERLOGGING" | "GARBAGE" | "BLOCKED_DRAIN" | "SEWAGE" | "STREET_LIGHT" | "DAMAGED_POLE" | "POWER_ISSUE" | "WATER_SUPPLY" | "PIPE_LEAK" | "FALLEN_TREE" | "BROKEN_FOOTPATH" | "ENCROACHMENT" | "BROKEN_PROPERTY" | "STRAY_ANIMALS" | "ROAD_SIGN" | "NOISE" | "OTHER",
  "severity": "LOW" | "MEDIUM" | "HIGH" | "EMERGENCY",
  "lf_item_type": "LOST" | "FOUND",
  "lf_category": "AADHAAR" | "MOBILE_PHONE" | "WALLET" | "KEYS" | "BAG" | "PET" | "JEWELLERY" | "VEHICLE" | "OTHER",
  "community_type": "GENERAL" | "POLL" | "ANNOUNCEMENT" | "JOB",
  "title": "<concise title, max 8 words>",
  "description": "<2-sentence clean factual summary>",
  "landmark": "<landmark if mentioned, otherwise null>",
  "tags": ["tag1", "tag2"]
}
''';

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [{'text': prompt}]
            }
          ],
          'generationConfig': {
            'temperature': 0.1,
            'maxOutputTokens': 400,
            'response_mime_type': 'application/json',
          },
        }),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final rawText = body['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
        if (rawText != null) {
          final cleanJson = rawText.replaceAll(RegExp(r'^```json\s*|\s*```$'), '').trim();
          final parsed = jsonDecode(cleanJson) as Map<String, dynamic>;

          final title = parsed['title']?.toString() ?? fallback.title;
          final desc = parsed['description']?.toString() ?? fallback.description;
          final landmark = parsed['landmark']?.toString() ?? fallback.extractedLandmark;
          final tags = (parsed['tags'] as List?)?.map((t) => t.toString()).toList() ?? fallback.tags;

          final catWire = parsed['civic_category']?.toString();
          final civicCat = catWire != null ? ReportCategory.fromWire(catWire) : fallback.civicCategory;

          final sevWire = parsed['severity']?.toString();
          final severity = sevWire != null ? Severity.fromWire(sevWire) : fallback.severity;

          final lfTypeWire = parsed['lf_item_type']?.toString();
          final lfItemType = lfTypeWire != null ? LFItemType.fromWire(lfTypeWire) : fallback.lfItemType;

          final lfCatWire = parsed['lf_category']?.toString();
          final lfCat = lfCatWire != null ? LFCategory.fromWire(lfCatWire) : fallback.lfCategory;

          final commWire = parsed['community_type']?.toString();
          final commType = commWire != null ? CommunityPostType.fromWire(commWire) : fallback.communityType;

          return fallback.copyWith(
            title: title,
            description: desc,
            civicCategory: civicCat,
            severity: severity,
            lfItemType: lfItemType,
            lfCategory: lfCat,
            communityType: commType,
            extractedLandmark: landmark,
            tags: tags,
            confidence: 0.98,
          );
        }
      }
    } catch (e) {
      debugPrint('[VoiceIntentParserService] Gemini parsing error: $e');
    }
    return null;
  }
}
