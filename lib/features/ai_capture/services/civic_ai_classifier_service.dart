import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/services/debug_logger.dart';
import '../../../models/enums.dart';
import '../models/civic_ai_models.dart';

final civicAiClassifierServiceProvider = Provider<CivicAiClassifierService>((ref) {
  return CivicAiClassifierService();
});

/// Real vision engine — sends camera JPEG frames to NVIDIA NIM
/// (llama-3.2-11b-vision-instruct via OpenAI-compatible API).
/// Only returns a detection when NIM confirms a genuine civic hazard is visible.
/// Returns null when nothing is detected.
class CivicAiClassifierService {
  // Last confirmed detection for display continuity
  CivicAiDetection? _lastConfirmedDetection;

  static const String _nimEndpoint =
      'https://integrate.api.nvidia.com/v1/chat/completions';
  static const String _nimModel = 'meta/llama-3.2-11b-vision-instruct';

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

  /// Prepares image bytes for NIM live scanning.
  /// If the camera snapshot is already reasonably sized (<= 450 KB), we preserve
  /// the native hardware-compressed JPEG to avoid bloated PNG conversions.
  /// If larger, we resize to 480px wide to minimize token usage.
  Future<_ResizeResult> _prepareLiveScanBytes(Uint8List original) async {
    if (original.lengthInBytes <= 450 * 1024) {
      return _ResizeResult(bytes: original, mimeType: 'image/jpeg');
    }

    try {
      final buffer = await ImmutableBuffer.fromUint8List(original);
      final descriptor = await ImageDescriptor.encoded(buffer);
      final srcW = descriptor.width;
      final srcH = descriptor.height;
      buffer.dispose();

      const targetW = 480;
      final targetH = (srcH * targetW / srcW).round();

      final codec = await descriptor.instantiateCodec(
        targetWidth: targetW,
        targetHeight: targetH,
      );
      descriptor.dispose();

      final frame = await codec.getNextFrame();
      codec.dispose();

      final byteData = await frame.image.toByteData(format: ImageByteFormat.png);
      frame.image.dispose();

      if (byteData != null) {
        return _ResizeResult(
          bytes: byteData.buffer.asUint8List(),
          mimeType: 'image/png',
        );
      }
    } catch (e) {
      DebugLogger.instance.log('NIM-SCAN', 'Resize error, keeping original: $e');
    }
    return _ResizeResult(bytes: original, mimeType: 'image/jpeg');
  }

  /// Real-time live frame scanner. Sends a frame to NVIDIA NIM (11B Vision).
  /// Returns a valid [CivicAiDetection] only if a genuine municipal hazard is
  /// detected with confidence >= 0.50.
  /// Returns null if no hazard is visible, confidence is low, or on network failure.
  Future<CivicAiDetection?> scanLiveFrame(
    XFile photo, {
    ReportCategory? hintCategory,
  }) async {
    final nimKey = dotenv.env['NVIDIA_NIM_API_KEY']?.trim();
    if (nimKey == null || nimKey.isEmpty) {
      DebugLogger.instance.log('NIM-SCAN', 'Missing NVIDIA_NIM_API_KEY in .env!');
      return null;
    }

    try {
      final file = File(photo.path);
      final originalBytes = await file.readAsBytes();
      // Clean up temporary preview snapshot file
      try {
        await file.delete();
      } catch (_) {}

      final prepared = await _prepareLiveScanBytes(originalBytes);
      DebugLogger.instance.log(
        'NIM-SCAN',
        'Live scan dispatching: original=${originalBytes.lengthInBytes}B, prepared=${prepared.bytes.lengthInBytes}B (${prepared.mimeType}), hint=${hintCategory?.wire ?? "auto"}',
      );

      final result = await _callNimVision(
        prepared.bytes,
        nimKey,
        hintCategory,
        highRes: false,
        minConfidence: 0.50,
        mimeType: prepared.mimeType,
      );
      if (result != null && result.isHazardDetected) {
        return result;
      }
      return null;
    } catch (e, stack) {
      DebugLogger.instance.error('NIM-SCAN', e, stack);
      return null;
    }
  }

  /// Calls NVIDIA NIM on a full-resolution captured photo for the review
  /// sheet. Returns a detection with validated civic category.
  Future<CivicAiDetection> classifyCapturedPhoto(
    XFile photo, {
    ReportCategory? hintCategory,
  }) async {
    // If we ALREADY have a high-confidence confirmed detection from the live scan
    // (within the last 8 seconds) and it's a specific civic hazard, use it immediately!
    // This makes review sheet presentation instantaneous (< 200ms) with zero timeout risk.
    if (_lastConfirmedDetection != null &&
        _lastConfirmedDetection!.isHazardDetected &&
        _lastConfirmedDetection!.category != ReportCategory.other &&
        _lastConfirmedDetection!.confidence >= 0.50) {
      final age = DateTime.now().difference(_lastConfirmedDetection!.timestamp).inSeconds;
      if (age <= 8) {
        DebugLogger.instance.log(
          'NIM-CAP',
          'Instant review sheet launch using live detection: ${_lastConfirmedDetection!.category.wire} ("${_lastConfirmedDetection!.title}")',
        );
        return _lastConfirmedDetection!.copyWith(
          isSteady: true,
          timestamp: DateTime.now(),
        );
      }
    }

    final nimKey = dotenv.env['NVIDIA_NIM_API_KEY']?.trim();
    if (nimKey != null && nimKey.isNotEmpty) {
      try {
        final bytes = await File(photo.path).readAsBytes();
        DebugLogger.instance.log(
          'NIM-CAP',
          'Classifying photo: ${photo.path} (${bytes.lengthInBytes} bytes), hint=${hintCategory?.wire ?? "auto"}',
        );

        final result = await _callNimVision(
          bytes,
          nimKey,
          hintCategory,
          highRes: true,
          minConfidence: 0.45,
        );

        if (result != null) {
          DebugLogger.instance.log(
            'NIM-CAP',
            'Capture classified: ${result.category.wire} (hazard: ${result.isHazardDetected}, conf: ${result.confidence.toStringAsFixed(2)}, sev: ${result.severity.wire})',
          );
          return result;
        }
      } catch (e, stack) {
        DebugLogger.instance.error('NIM-CAP', e, stack);
      }
    } else {
      DebugLogger.instance.log('NIM-CAP', 'NVIDIA_NIM_API_KEY is empty/null');
    }

    // Fallback: use the last live detection if available AND it was a genuine confirmed hazard
    if (_lastConfirmedDetection != null && _lastConfirmedDetection!.isHazardDetected) {
      DebugLogger.instance.log(
        'NIM-CAP',
        'Using last confirmed live detection fallback: ${_lastConfirmedDetection!.category.wire}',
      );
      return _lastConfirmedDetection!.copyWith(
        isSteady: true,
        timestamp: DateTime.now(),
      );
    }

    // If the user explicitly picked a category tab (e.g. Broken Footpath),
    // provide manual preset detection without pretending high AI confidence.
    if (hintCategory != null) {
      final preset = getPresetMetadata(hintCategory);
      DebugLogger.instance.log('NIM-CAP', 'Using targeted hint category: ${hintCategory.wire}');
      return CivicAiDetection(
        category: hintCategory,
        confidence: 0.50,
        severity: Severity.medium,
        title: preset.title,
        description: preset.description,
        titleMl: preset.titleMl,
        descriptionMl: preset.descriptionMl,
        boundingBox: const Rect.fromLTWH(0.2, 0.25, 0.6, 0.5),
        visualEvidenceTags: preset.defaultTags,
        timestamp: DateTime.now(),
        isSteady: true,
        isHazardDetected: true,
      );
    }

    // In Auto mode: if no hazard was recognized, NEVER default to Pothole!
    DebugLogger.instance.log('NIM-CAP', 'No municipal hazard detected in image. Returning noHazard.');
    return CivicAiDetection.noHazard(
      reason: 'No municipal hazard detected. Camera appears to be pointing at a non-civic or indoor scene.',
    );
  }

  /// Core NVIDIA NIM Vision API call (OpenAI-compatible chat completions with
  /// base64 inline image using llama-3.2-11b-vision-instruct).
  /// Returns null if the scene contains no recognisable civic hazard.
  Future<CivicAiDetection?> _callNimVision(
    Uint8List imageBytes,
    String apiKey,
    ReportCategory? targetedCategory, {
    bool highRes = false,
    double minConfidence = 0.70,
    String mimeType = 'image/jpeg',
  }) async {
    try {
      final base64Image = base64Encode(imageBytes);
      final validWires = ReportCategory.values.map((c) => c.wire).toList();

      final categoryHint = targetedCategory != null
          ? 'Focus specifically on checking if this image contains: ${targetedCategory.wire}. '
          : '';

      const systemPrompt =
          'You are an expert municipal hazard inspector for the Nivara civic app. '
          'Classify the image into one of the exact allowed civic categories. '
          'Respond ONLY with a valid raw JSON object. Never output markdown or extra text.';

      final userPrompt = '''
Analyze this image for civic/municipal hazards in public spaces (potholes, open drains, garbage dumps, waterlogging, street light damage, etc.).
$categoryHint
Allowed categories (use exact wire names):
${validWires.join(', ')}, or "not_a_civic_issue" if no hazard is visible (e.g. clean indoor room, clear road).

Respond ONLY with this raw JSON:
{
  "category": "<one of the exact uppercase wire values above OR 'not_a_civic_issue'>",
  "severity": "LOW" | "MEDIUM" | "HIGH" | "EMERGENCY",
  "confidence": 0.0 to 1.0,
  "title_en": "<concise title>",
  "description_en": "<factual description>",
  "title_ml": "<Malayalam title or empty>",
  "description_ml": "<Malayalam description or empty>",
  "tags": ["tag1", "tag2"],
  "reasoning": "<brief reasoning>"
}
''';

      final stopwatch = Stopwatch()..start();
      DebugLogger.instance.log(
        'NIM-API',
        'POST to NIM ($_nimModel, mime=$mimeType, bytes=${imageBytes.lengthInBytes}, hint=${targetedCategory?.wire ?? "none"})...',
      );

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
                        'url': 'data:$mimeType;base64,$base64Image',
                      },
                    },
                  ],
                },
              ],
              'temperature': 0.0,
              'max_tokens': 300,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 35));

      final elapsed = stopwatch.elapsedMilliseconds;
      if (response.statusCode != 200) {
        DebugLogger.instance.log(
          'NIM-API',
          'NIM HTTP ${response.statusCode} in ${elapsed}ms: ${response.body}',
        );
        return null;
      }

      final body = jsonDecode(response.body);
      final rawText =
          body['choices']?[0]?['message']?['content'] as String?;
      if (rawText == null || rawText.trim().isEmpty) {
        DebugLogger.instance.log('NIM-API', 'Empty response content in ${elapsed}ms');
        return null;
      }

      // Robustly extract JSON object using RegExp to handle any markdown or conversational preamble
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(rawText);
      if (jsonMatch == null) {
        DebugLogger.instance.log('NIM-API', 'No JSON found in ${elapsed}ms: $rawText');
        return null;
      }
      final cleanJson = jsonMatch.group(0)!;
      final parsed = jsonDecode(cleanJson) as Map<String, dynamic>;

      final rawCat = (parsed['category']?.toString() ?? '').trim();
      final titleEn = (parsed['title_en']?.toString() ?? '').trim();
      final descEn = (parsed['description_en']?.toString() ?? '').trim();
      final titleMl = (parsed['title_ml']?.toString() ?? '').trim();
      final descMl = (parsed['description_ml']?.toString() ?? '').trim();
      final tags = (parsed['tags'] as List?)?.map((t) => t.toString().trim()).toList() ?? [];
      final reasoning = (parsed['reasoning']?.toString() ?? '').trim();

      // Check for explicit negative/non-civic signals from NIM
      final isExplicitNegative = rawCat.toLowerCase() == 'not_a_civic_issue' ||
          rawCat.toLowerCase() == 'none' ||
          rawCat.toLowerCase() == 'null' ||
          rawCat.toLowerCase() == 'clear' ||
          rawCat.toLowerCase() == 'no_issue' ||
          rawCat.toLowerCase() == 'not_civic';

      final allText = '${rawCat.toLowerCase()} ${titleEn.toLowerCase()} ${descEn.toLowerCase()} ${reasoning.toLowerCase()}';
      final isIndoorOrNonHazard = allText.contains('laptop') ||
          allText.contains('desk') ||
          allText.contains('table') ||
          allText.contains('room') ||
          allText.contains('computer') ||
          allText.contains('study table') ||
          allText.contains('keyboard') ||
          allText.contains('monitor') ||
          allText.contains('not a civic') ||
          allText.contains('not a municipal') ||
          allText.contains('not a hazard') ||
          allText.contains('no civic') ||
          allText.contains('indoor');

      if (isExplicitNegative || isIndoorOrNonHazard) {
        DebugLogger.instance.log(
          'NIM-API',
          'Negative civic confirmation in ${elapsed}ms: $rawCat ($reasoning)',
        );
        final cleanReason = reasoning.isNotEmpty
            ? reasoning
            : 'No municipal hazard detected in this frame (indoor or non-civic scene).';
        return CivicAiDetection.noHazard(
          reason: cleanReason,
        );
      }

      // Intelligently resolve the exact civic category using both raw category & title/desc/tags
      final category = resolveCivicCategory(
        rawCat: rawCat,
        title: titleEn,
        desc: descEn,
        tags: tags,
      );

      if (category == ReportCategory.other) {
        DebugLogger.instance.log(
          'NIM-API',
          'Could not map to official civic category: rawCat="$rawCat", title="$titleEn"',
        );
        return CivicAiDetection.noHazard(
          reason: reasoning.isNotEmpty
              ? reasoning
              : 'The scene does not match any official municipal hazard category.',
        );
      }

      final sevWire = parsed['severity']?.toString();
      final severity = Severity.fromWire(sevWire);
      final conf = ((parsed['confidence'] as num?)?.toDouble() ?? 0.85)
          .clamp(0.0, 0.99);

      DebugLogger.instance.log(
        'NIM-API',
        'NIM 11B detected in ${elapsed}ms: rawCat="$rawCat", title="$titleEn" → ${category.wire} (${category.label}), conf=${conf.toStringAsFixed(2)}, sev=${severity.wire}, minConf=$minConfidence',
      );

      // Filter out low confidence detections
      if (conf < minConfidence) {
        DebugLogger.instance.log('NIM-API', 'Confidence $conf below threshold $minConfidence, discarded.');
        return CivicAiDetection.noHazard(
          reason: 'Hazard detected with low confidence (${(conf * 100).toInt()}%). Please capture closer.',
        );
      }

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
        isHazardDetected: true,
      );

      // Cache for display continuity and instant review sheet launch
      _lastConfirmedDetection = detection;
      return detection;
    } catch (e, stack) {
      DebugLogger.instance.error('NIM-API', e, stack);
      return null;
    }
  }

  /// Multi-signal category resolver that maps NIM responses, titles, descriptions,
  /// and tags to Nivara's 19 official ReportCategory values.
  static ReportCategory resolveCivicCategory({
    String rawCat = '',
    String title = '',
    String desc = '',
    List<String> tags = const [],
  }) {
    // 1. Direct fromWire match on rawCat
    if (rawCat.isNotEmpty &&
        rawCat.toLowerCase() != 'not_a_civic_issue' &&
        rawCat.toLowerCase() != 'other') {
      final direct = ReportCategory.fromWire(rawCat);
      if (direct != ReportCategory.other) {
        return direct;
      }
    }

    // 2. Check title, description, and tags for civic hazard keywords
    final text = '${rawCat.toLowerCase()} ${title.toLowerCase()} ${desc.toLowerCase()} ${tags.map((t) => t.toLowerCase()).join(' ')}';

    if (text.contains('footpath') || text.contains('sidewalk') || text.contains('pavement') || text.contains('walkway')) {
      return ReportCategory.brokenFootpath;
    }
    if (text.contains('manhole') || text.contains('drain cover') || text.contains('sewer cover') || text.contains('sewer opening')) {
      return ReportCategory.openManhole;
    }
    if (text.contains('pothole') || text.contains('crater') || text.contains('road cavity') || text.contains('asphalt hole')) {
      return ReportCategory.pothole;
    }
    if (text.contains('waterlog') || text.contains('flooding') || text.contains('water puddle') || text.contains('stagnant water') || text.contains('standing water')) {
      return ReportCategory.waterlogging;
    }
    if (text.contains('fallen tree') || text.contains('tree hazard') || text.contains('tree branch') || text.contains('fallen branch') || text.contains('uprooted tree')) {
      return ReportCategory.fallenTree;
    }
    if (text.contains('street light') || text.contains('streetlight') || text.contains('lamp post') || text.contains('broken light') || text.contains('unlit light') || text.contains('dark street')) {
      return ReportCategory.streetLight;
    }
    if (text.contains('blocked drain') || text.contains('clogged drain') || text.contains('drainage') || text.contains('open drain') || text.contains('gutter') || text.contains('culvert')) {
      return ReportCategory.blockedDrain;
    }
    if (text.contains('garbage') || text.contains('trash') || text.contains('waste') || text.contains('rubbish') || text.contains('dump') || text.contains('litter')) {
      return ReportCategory.garbage;
    }
    if (text.contains('sewage') || text.contains('blackwater') || text.contains('septic') || text.contains('waste water') || text.contains('wastewater')) {
      return ReportCategory.sewage;
    }
    if (text.contains('damaged pole') || text.contains('electric pole') || text.contains('tilted pole') || text.contains('broken pole') || text.contains('utility pole') || text.contains('pole')) {
      return ReportCategory.damagedPole;
    }
    if (text.contains('power issue') || text.contains('electric wire') || text.contains('hanging wire') || text.contains('loose cable') || text.contains('live wire') || text.contains('dangling cable') || text.contains('power cut')) {
      return ReportCategory.powerIssue;
    }
    if (text.contains('pipe leak') || text.contains('pipeline leak') || text.contains('burst pipe') || text.contains('water pipe') || text.contains('water leak')) {
      return ReportCategory.pipeLeak;
    }
    if (text.contains('water supply') || text.contains('drinking water') || text.contains('water shortage') || text.contains('water crisis')) {
      return ReportCategory.waterSupply;
    }
    if (text.contains('road sign') || text.contains('signboard') || text.contains('traffic sign') || text.contains('damaged sign')) {
      return ReportCategory.roadSign;
    }
    if (text.contains('encroach') || text.contains('illegal structure') || text.contains('footpath block') || text.contains('hawker')) {
      return ReportCategory.encroachment;
    }
    if (text.contains('broken property') || text.contains('bus shelter') || text.contains('vandal') || text.contains('broken bench') || text.contains('damaged railing')) {
      return ReportCategory.brokenProperty;
    }
    if (text.contains('stray') || text.contains('stray animal') || text.contains('stray dog') || text.contains('cattle') || text.contains('cows on road') || text.contains('dog')) {
      return ReportCategory.strayAnimals;
    }
    if (text.contains('noise') || text.contains('loudspeaker') || text.contains('generator noise') || text.contains('decibel')) {
      return ReportCategory.noise;
    }

    return ReportCategory.other;
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

/// Internal helper returned by [CivicAiClassifierService._resizeForNimLiveScan].
/// Carries the (possibly resized) image bytes and the correct MIME type to use
/// in the NIM API request.
class _ResizeResult {
  const _ResizeResult({required this.bytes, required this.mimeType});
  final Uint8List bytes;
  final String mimeType;
}
