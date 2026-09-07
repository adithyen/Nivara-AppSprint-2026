import 'dart:ui';
import '../../../models/enums.dart';

/// Represents a real-time hazard detection from the AI vision pipeline.
class CivicAiDetection {
  final ReportCategory category;
  final double confidence;
  final Severity severity;
  final String title;
  final String description;
  final String titleMl;
  final String descriptionMl;
  final Rect? boundingBox;
  final List<String> visualEvidenceTags;
  final DateTime timestamp;
  final bool isSteady;

  const CivicAiDetection({
    required this.category,
    required this.confidence,
    required this.severity,
    required this.title,
    required this.description,
    required this.titleMl,
    required this.descriptionMl,
    this.boundingBox,
    this.visualEvidenceTags = const [],
    required this.timestamp,
    this.isSteady = false,
  });

  /// True if confidence is high enough for automatic lock & capture (>= 85%).
  bool get isHighConfidence => confidence >= 0.85;

  CivicAiDetection copyWith({
    ReportCategory? category,
    double? confidence,
    Severity? severity,
    String? title,
    String? description,
    String? titleMl,
    String? descriptionMl,
    Rect? boundingBox,
    List<String>? visualEvidenceTags,
    DateTime? timestamp,
    bool? isSteady,
  }) {
    return CivicAiDetection(
      category: category ?? this.category,
      confidence: confidence ?? this.confidence,
      severity: severity ?? this.severity,
      title: title ?? this.title,
      description: description ?? this.description,
      titleMl: titleMl ?? this.titleMl,
      descriptionMl: descriptionMl ?? this.descriptionMl,
      boundingBox: boundingBox ?? this.boundingBox,
      visualEvidenceTags: visualEvidenceTags ?? this.visualEvidenceTags,
      timestamp: timestamp ?? this.timestamp,
      isSteady: isSteady ?? this.isSteady,
    );
  }
}

/// The complete payload generated after capturing an evidence frame with AI metadata.
class CivicAiCapturePayload {
  final String photoPath;
  final CivicAiDetection detection;
  final double lat;
  final double lng;
  final String? address;
  final DateTime capturedAt;

  const CivicAiCapturePayload({
    required this.photoPath,
    required this.detection,
    required this.lat,
    required this.lng,
    this.address,
    required this.capturedAt,
  });
}
