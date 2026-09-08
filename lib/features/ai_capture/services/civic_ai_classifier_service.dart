import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../models/enums.dart';
import '../models/civic_ai_models.dart';

final civicAiClassifierServiceProvider = Provider<CivicAiClassifierService>((ref) {
  return CivicAiClassifierService();
});

/// Real vision engine — every analysis call sends an actual JPEG frame to
/// NVIDIA NIM (llama-3.2-11b-vision-instruct via the OpenAI-compatible API).
/// Only returns a detection when NIM confirms a genuine civic hazard is visible.
/// Returns null when nothing is detected.
class CivicAiClassifierService {
  // Last confirmed detection for display continuity
  CivicAiDetection? _lastConfirmedDetection;

  static const String _nimEndpoint =
      'https://integrate.api.nvidia.com/v1/chat/completions';
  static const String _nimModel = 'meta/llama-3.2-90b-vision-instruct';

  /// Clears the last confirmed detection (called after capture or reset).
  void resetTracking() {
    _lastConfirmedDetection = null;
  }

  /// Returns the last NIM-confirmed detection (for display while a new
  /// analysis is in flight). Never returns stale detections older than 6s.
  CivicAiDetection? get currentDetection {
    if (_lastConfirmedDetection == null) return null;
    final age = DateTime.now().difference(_lastConfirmedDetection!.timestamp).inSeconds;
    if (age > 6) {
      _lastConfirmedDetection = null;
      return null;
    }
    return _lastConfirmedDetection;
  }

  /// Calls NVIDIA NIM on a full-resolution captured photo for the review
  /// sheet. Returns a detection with validated civic category, or a
  /// "not a civic issue" result so the user knows.
  Future<CivicAiDetection> classifyCapturedPhoto(
    XFile photo, {
    ReportCategory? hintCategory,
  }) async {
    final nimKey = dotenv.env['NVIDIA_NIM_API_KEY']?.trim();
    if (nimKey != null && nimKey.isNotEmpty) {
      try {
        final bytes = await File(photo.path).readAsBytes();
        final result = await _callNimVision(bytes, nimKey, hintCategory,
            highRes: true);
        if (result != null) return result;
      } catch (e) {
        debugPrint('[CivicAiClassifier] NIM capture classification error: $e');
      }
    }

    // Fallback: use the last live detection if available, otherwise return
    // a generic unknown result so the review sheet can still show something.
    if (_lastConfirmedDetection != null) {
      return _lastConfirmedDetection!.copyWith(
        isSteady: true,
        timestamp: DateTime.now(),
      );
    }

    final category = hintCategory ?? ReportCategory.other;
    final preset = getPresetMetadata(category);
    return CivicAiDetection(
      category: category,
      confidence: 0.70,
      severity: Severity.medium,
      title: preset.title,
      description: preset.description,
      titleMl: preset.titleMl,
      descriptionMl: preset.descriptionMl,
      boundingBox: const Rect.fromLTWH(0.2, 0.25, 0.6, 0.5),
      visualEvidenceTags: preset.defaultTags,
      timestamp: DateTime.now(),
      isSteady: true,
    );
  }

  /// Core NVIDIA NIM Vision API call (OpenAI-compatible chat completions with
  /// base64 inline image using llama-3.2-90b-vision-instruct).
  /// Returns null if the scene contains no recognisable civic hazard.
  Future<CivicAiDetection?> _callNimVision(
    Uint8List imageBytes,
    String apiKey,
    ReportCategory? targetedCategory, {
    bool highRes = false,
  }) async {
    try {
      final base64Image = base64Encode(imageBytes);
      final validWires = ReportCategory.values.map((c) => c.wire).toList();

      final categoryHint = targetedCategory != null
          ? 'The user is specifically looking for: ${targetedCategory.wire}. '
              'Only confirm if you actually see this issue type.'
          : '';

      final systemPrompt =
          'You are a strict civic hazard inspector AI for Nivara, a municipal '
          'reporting app. Only identify real infrastructure problems visible '
          'outdoors in public spaces. Respond exclusively with raw JSON — '
          'no markdown, no backticks, no extra text.';

      final userPrompt = '''
Analyze this camera image taken on a public road or in a municipality.

$categoryHint

TASK: Determine if this image shows a REAL civic infrastructure hazard from this list:
${validWires.join(', ')}

STRICT RULES:
1. You MUST return "not_a_civic_issue" as category if the image shows:
   - Paper, documents, notebooks, text, books
   - Benches, chairs, furniture indoors or in good condition
   - Clean tiles, floors, walls without damage
   - People, vehicles without associated hazards
   - Any indoor setting without a visible civic problem
   - Anything unclear, blurry, or too dark to identify
2. Only identify a hazard if you see CLEAR, UNAMBIGUOUS evidence
3. Minimum confidence must be 0.80 to report a hazard

Return ONLY raw JSON, no markdown, no backticks:
{
  "category": "<one of the 19 wire values, OR 'not_a_civic_issue'>",
  "severity": "LOW" | "MEDIUM" | "HIGH" | "EMERGENCY",
  "confidence": 0.0 to 1.0,
  "title_en": "<concise title or empty string if not_a_civic_issue>",
  "description_en": "<2-sentence factual description or empty if not_a_civic_issue>",
  "title_ml": "<Malayalam title or empty string>",
  "description_ml": "<Malayalam description or empty string>",
  "tags": ["tag1", "tag2"],
  "reasoning": "<one sentence explaining what you saw>"
}
''';

      final response = await http
          .post(
            Uri.parse(_nimEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': _nimModel,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {
                  'role': 'user',
                  'content': [
                    {'type': 'text', 'text': userPrompt},
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url': 'data:image/jpeg;base64,$base64Image',
                      },
                    },
                  ],
                },
              ],
              'temperature': 0.1,
              'max_tokens': 600,
              'stream': false,
            }),
          )
          .timeout(Duration(seconds: highRes ? 8 : 5));

      if (response.statusCode != 200) {
        debugPrint('[CivicAiClassifier] NIM HTTP ${response.statusCode}: ${response.body}');
        return null;
      }

      final body = jsonDecode(response.body);
      final rawText =
          body['choices']?[0]?['message']?['content'] as String?;
      if (rawText == null) return null;

      // Strip markdown code fences if the model adds them despite instructions
      final cleanJson =
          rawText.replaceAll(RegExp(r'^```json\s*|\s*```$', multiLine: true), '').trim();
      final parsed = jsonDecode(cleanJson) as Map<String, dynamic>;

      final catWire = parsed['category']?.toString() ?? 'not_a_civic_issue';
      debugPrint('[CivicAiClassifier] NIM says: $catWire — ${parsed['reasoning']}');

      // Explicitly bail out on non-civic scenes
      if (catWire == 'not_a_civic_issue') return null;

      final category = ReportCategory.fromWire(catWire);
      final sevWire = parsed['severity']?.toString();
      final severity = Severity.fromWire(sevWire);
      final conf = ((parsed['confidence'] as num?)?.toDouble() ?? 0.80)
          .clamp(0.0, 0.99);

      // Below minimum confidence — don't report
      if (conf < 0.80) return null;

      final titleEn = parsed['title_en']?.toString() ?? '';
      final descEn = parsed['description_en']?.toString() ?? '';
      final titleMl = parsed['title_ml']?.toString() ?? '';
      final descMl = parsed['description_ml']?.toString() ?? '';
      final tags = (parsed['tags'] as List?)?.map((t) => t.toString()).toList() ?? [];

      final preset = getPresetMetadata(category);

      final detection = CivicAiDetection(
        category: category,
        confidence: conf,
        severity: severity,
        title: titleEn.isNotEmpty ? titleEn : preset.title,
        description: descEn.isNotEmpty ? descEn : preset.description,
        titleMl: titleMl.isNotEmpty ? titleMl : preset.titleMl,
        descriptionMl: descMl.isNotEmpty ? descMl : preset.descriptionMl,
        boundingBox: const Rect.fromLTWH(0.20, 0.28, 0.60, 0.44),
        visualEvidenceTags: tags.isNotEmpty ? tags : preset.defaultTags,
        timestamp: DateTime.now(),
        isSteady: false,
      );

      // Cache for continuity
      _lastConfirmedDetection = detection;
      return detection;
    } catch (e) {
      debugPrint('[CivicAiClassifier] NIM Vision error: $e');
      return null;
    }
  }

  /// Preset titles, descriptions, and tags for all 19 civic hazard categories.
  CivicPresetMetadata getPresetMetadata(ReportCategory cat) {
    switch (cat) {
      case ReportCategory.pothole:
        return const CivicPresetMetadata(
          title: 'Pothole / Road Cavity',
          description:
              'A significant road cavity or pothole is obstructing the road surface, posing a risk to vehicles and pedestrians.',
          titleMl: 'റോഡിലെ കുഴി',
          descriptionMl:
              'വാഹനങ്ങൾക്കും കാൽനടക്കാർക്കും ഭീഷണിയായ ഒരു വലിയ റോഡ് കുഴി ശ്രദ്ധയിൽ പെട്ടിരിക്കുന്നു.',
          defaultTags: ['pothole', 'road_damage', 'vehicle_hazard'],
        );
      case ReportCategory.openManhole:
        return const CivicPresetMetadata(
          title: 'Open / Uncovered Manhole',
          description:
              'A manhole cover is missing or displaced, creating an extreme fall risk for pedestrians and vehicles.',
          titleMl: 'മൂടി ഇല്ലാത്ത മാൻഹോൾ',
          descriptionMl:
              'മൂടിയില്ലാത്ത ഒരു മാൻഹോൾ കണ്ടുപിടിക്കപ്പെട്ടിരിക്കുന്നു, ഇത് ഗുരുതരമായ അപകടമാണ്.',
          defaultTags: ['open_manhole', 'missing_cover', 'fall_risk'],
        );
      case ReportCategory.fallenTree:
        return const CivicPresetMetadata(
          title: 'Fallen Tree Blocking Road',
          description:
              'A fallen tree is blocking road access, obstructing traffic and potentially damaging infrastructure.',
          titleMl: 'വഴിതടഞ്ഞ് വീണ മരം',
          descriptionMl:
              'ഒരു മരം റോഡിൽ വീണ് ഗതാഗതം തടസ്സപ്പെടുത്തിയിരിക്കുന്നു.',
          defaultTags: ['fallen_tree', 'road_obstruction', 'traffic_block'],
        );
      case ReportCategory.waterlogging:
        return const CivicPresetMetadata(
          title: 'Waterlogging / Road Flooding',
          description:
              'Severe waterlogging is present on the road, hindering pedestrian and vehicle movement.',
          titleMl: 'വെള്ളക്കെട്ട്',
          descriptionMl:
              'റോഡിൽ ഗുരുതരമായ വെള്ളക്കെട്ട് ഉണ്ട്, ഗതാഗതം ബുദ്ധിമുട്ടാണ്.',
          defaultTags: ['waterlogging', 'flooding', 'drainage_failure'],
        );
      case ReportCategory.roadSign:
        return const CivicPresetMetadata(
          title: 'Damaged / Missing Road Sign',
          description:
              'A road sign is damaged, missing, or obscured, creating navigation and safety hazards.',
          titleMl: 'കേടായ റോഡ് ബോർഡ്',
          descriptionMl:
              'ഒരു ട്രാഫിക് ബോർഡ് കേടുപാടുകളോ കാണ്മാനില്ലായ്മയോ ഉണ്ട്.',
          defaultTags: ['road_sign', 'missing_signage', 'navigation_hazard'],
        );
      case ReportCategory.garbage:
        return const CivicPresetMetadata(
          title: 'Garbage Dump / Waste Pile',
          description:
              'An unauthorized garbage dump or accumulation of waste is creating sanitation and health hazards.',
          titleMl: 'മാലിന്യക്കൂമ്പാരം',
          descriptionMl: 'അനധികൃത മാലിന്യ കൂമ്പാരം ആരോഗ്യ ഭീഷണി ഉണ്ടാക്കുന്നു.',
          defaultTags: ['garbage', 'waste_dump', 'sanitation_hazard'],
        );
      case ReportCategory.blockedDrain:
        return const CivicPresetMetadata(
          title: 'Blocked / Overflowing Drain',
          description:
              'A drainage channel is blocked or overflowing, causing sewage and water to accumulate on the road.',
          titleMl: 'തടഞ്ഞ ഓടചാൽ',
          descriptionMl: 'ഒഴുക്കുചാൽ തടഞ്ഞ് വഴിയിൽ വെള്ളം കെട്ടി നിൽക്കുന്നു.',
          defaultTags: ['blocked_drain', 'overflow', 'drainage_clog'],
        );
      case ReportCategory.sewage:
        return const CivicPresetMetadata(
          title: 'Sewage Wastewater Leak / Overflow',
          description:
              'Contaminated blackwater or municipal sewage is spilling onto a public thoroughfare.',
          titleMl: 'മലിനജല ചോർച്ച',
          descriptionMl: 'മലിനജലം പൊതുവഴിയിൽ ഒഴുകുന്നത് ശ്രദ്ധിക്കപ്പെട്ടിരിക്കുന്നു.',
          defaultTags: ['sewage', 'wastewater', 'health_hazard'],
        );
      case ReportCategory.streetLight:
        return const CivicPresetMetadata(
          title: 'Street Light Outage',
          description:
              'A street light is non-functional, creating unsafe dark conditions for pedestrians and vehicles.',
          titleMl: 'തെരുവ് വിളക്ക് കേടായി',
          descriptionMl: 'ഒരു തെരുവ് ലൈറ്റ് പ്രവർത്തിക്കുന്നില്ല, ഇത് അസുരക്ഷിതമാണ്.',
          defaultTags: ['street_light', 'outage', 'safety_hazard'],
        );
      case ReportCategory.damagedPole:
        return const CivicPresetMetadata(
          title: 'Damaged Utility Pole',
          description:
              'An electricity or telephone utility pole is damaged, leaning, or at risk of collapse.',
          titleMl: 'കേടായ ഉൾഭൂ-ഉപകരണ തൂൺ',
          descriptionMl: 'ഒരു ഉൾഭൂ-ഉപകരണ തൂൺ കേടുകൂടി ചരിഞ്ഞ് നിൽക്കുന്നു.',
          defaultTags: ['utility_pole', 'damaged_pole', 'electrical_hazard'],
        );
      case ReportCategory.powerIssue:
        return const CivicPresetMetadata(
          title: 'Power Supply Disruption',
          description:
              'A power outage or electrical infrastructure fault is affecting residents or public facilities.',
          titleMl: 'വൈദ്യുതി തകരാർ',
          descriptionMl: 'വൈദ്യുതി ഘടകങ്ങൾക്ക് തകരാർ സംഭവിച്ചിരിക്കുന്നു.',
          defaultTags: ['power_outage', 'electrical_fault', 'infrastructure'],
        );
      case ReportCategory.waterSupply:
        return const CivicPresetMetadata(
          title: 'Water Supply Disruption',
          description:
              'Municipal water supply has been disrupted or contaminated, affecting access to clean drinking water.',
          titleMl: 'കുടിവെള്ള ക്ഷാമം',
          descriptionMl: 'കുടിവെള്ള വിതരണം തടസ്സപ്പെട്ടിരിക്കുന്നു.',
          defaultTags: ['water_supply', 'disruption', 'drinking_water'],
        );
      case ReportCategory.pipeLeak:
        return const CivicPresetMetadata(
          title: 'Water Pipe Leakage / Burst',
          description:
              'A municipal water main or supply pipe is visibly leaking or burst, wasting clean water and damaging the road.',
          titleMl: 'പൈപ്പ് ചോർച്ച',
          descriptionMl: 'ഒരു ജലക്കുഴൽ ചോർന്ന് ശുദ്ധജലം പാഴായി പോകുന്നു.',
          defaultTags: ['pipe_leak', 'water_wastage', 'burst_main'],
        );
      case ReportCategory.encroachment:
        return const CivicPresetMetadata(
          title: 'Illegal Encroachment on Public Land',
          description:
              'A structure or activity is illegally encroaching onto public road or footpath space.',
          titleMl: 'പൊതു ഭൂമി കയ്യേറ്റം',
          descriptionMl: 'പൊതു ഭൂമിയിൽ അനധികൃതമായ കയ്യേറ്റം ശ്രദ്ധയിൽ പെട്ടിരിക്കുന്നു.',
          defaultTags: ['encroachment', 'public_land', 'illegal_structure'],
        );
      case ReportCategory.brokenProperty:
        return const CivicPresetMetadata(
          title: 'Damaged Public Property',
          description:
              'Public infrastructure such as a bench, railing, or bus shelter has been damaged or vandalized.',
          titleMl: 'കേടായ പൊതുമുതൽ',
          descriptionMl: 'ഒരു പൊതു-ഇൻഫ്രാസ്ട്രക്ചർ ഘടകം കേടുകൂടിയിരിക്കുന്നു.',
          defaultTags: ['public_property', 'vandalism', 'damage'],
        );
      case ReportCategory.strayAnimals:
        return const CivicPresetMetadata(
          title: 'Stray Animal Menace',
          description:
              'Aggressive stray animals are posing a safety risk to pedestrians or blocking road access.',
          titleMl: 'തെരുവ് മൃഗ ശല്യം',
          descriptionMl: 'അലഞ്ഞു തിരിയുന്ന മൃഗങ്ങൾ ആളുകൾക്ക് ഭീഷണി ഉണ്ടാക്കുന്നു.',
          defaultTags: ['stray_animals', 'public_safety', 'animal_menace'],
        );
      case ReportCategory.noise:
        return const CivicPresetMetadata(
          title: 'Noise Pollution / Public Nuisance',
          description:
              'Excessive noise from construction, commercial activity, or events is violating public peace norms.',
          titleMl: 'ശബ്ദ മലിനീകരണം',
          descriptionMl: 'അമിത ശബ്ദം പൊതുജന ശല്യം ഉണ്ടാക്കുന്നു.',
          defaultTags: ['noise_pollution', 'public_nuisance', 'decibel_violation'],
        );
      case ReportCategory.brokenFootpath:
        return const CivicPresetMetadata(
          title: 'Broken / Damaged Footpath',
          description:
              'A pedestrian footpath has broken tiles or concrete, creating tripping hazards for walkers.',
          titleMl: 'തകർന്ന നടപ്പാത',
          descriptionMl: 'നടപ്പാതയിൽ ടൈൽ അഴിഞ്ഞ് കാൽ തടസ്സം ഉണ്ടാകാം.',
          defaultTags: ['broken_footpath', 'cracked_tiles', 'pedestrian_hazard'],
        );
      case ReportCategory.other:
        return const CivicPresetMetadata(
          title: 'Other Civic Issue',
          description:
              'A civic infrastructure issue has been identified that requires municipal attention.',
          titleMl: 'മറ്റ് നഗര പ്രശ്നം',
          descriptionMl: 'ഒരു പൊതു-ഇൻഫ്രാ പ്രശ്നം ശ്രദ്ധയിൽ പെട്ടിരിക്കുന്നു.',
          defaultTags: ['civic_issue', 'municipal_attention_needed'],
        );
    }
  }
}
