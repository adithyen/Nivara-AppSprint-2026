import '../core/utils.dart';
import 'enums.dart';
import 'evidence_package.dart';

/// A civic complaint — a row of `reports`. Filed manually or auto-submitted
/// from SensorWatch. The DB fills `location`, `assigned_department`,
/// `updated_at` via triggers, so those are read-only from the app's side.
class Report {
  final String id;
  final String? userId;
  final ReportCategory category;
  final ReportStatus status;
  final Severity severity;
  final String? title;
  final String? description;

  final double lat;
  final double lng;
  final String? address;
  final String? city;
  final String? ward;

  /// 'SENSORWATCH' | 'MANUAL'.
  final String source;
  final DetectionType? detectionType;
  final EvidencePackage? evidencePackage;
  final String? evidenceHash;
  final List<String>? photoUrls;

  final int confirmationCount;
  final int resolvedCount;
  final bool isCommunityVerified;

  final AdminDepartment? assignedDepartment;
  final String? assignedTo;
  final DateTime? acknowledgedAt;
  final DateTime? resolvedAt;
  final String? resolutionNotes;
  final String? resolutionPhoto;

  final DateTime createdAt;
  final DateTime? updatedAt;

  const Report({
    required this.id,
    this.userId,
    required this.category,
    this.status = ReportStatus.submitted,
    this.severity = Severity.medium,
    this.title,
    this.description,
    required this.lat,
    required this.lng,
    this.address,
    this.city,
    this.ward,
    this.source = 'MANUAL',
    this.detectionType,
    this.evidencePackage,
    this.evidenceHash,
    this.photoUrls,
    this.confirmationCount = 0,
    this.resolvedCount = 0,
    this.isCommunityVerified = false,
    this.assignedDepartment,
    this.assignedTo,
    this.acknowledgedAt,
    this.resolvedAt,
    this.resolutionNotes,
    this.resolutionPhoto,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isFromSensor => source == 'SENSORWATCH';
  bool get hasEvidence => evidenceHash != null;
  bool get isOpen =>
      status != ReportStatus.resolved &&
      status != ReportStatus.closed &&
      status != ReportStatus.duplicate;

  factory Report.fromMap(Map<String, dynamic> map) {
    final ep = map['evidence_package'];
    return Report(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      category: ReportCategory.fromWire(map['category'] as String?),
      status: ReportStatus.fromWire(map['status'] as String?),
      severity: Severity.fromWire(map['severity'] as String?),
      title: map['title'] as String?,
      description: map['description'] as String?,
      lat: toDouble(map['lat']),
      lng: toDouble(map['lng']),
      address: map['address'] as String?,
      city: map['city'] as String?,
      ward: map['ward'] as String?,
      source: (map['source'] as String?) ?? 'MANUAL',
      detectionType: DetectionType.fromWire(map['detection_type'] as String?),
      evidencePackage: ep is Map<String, dynamic>
          ? EvidencePackage.fromMap(ep)
          : null,
      evidenceHash: map['evidence_hash'] as String?,
      photoUrls: toStringListOrNull(map['photo_urls']),
      confirmationCount: toInt(map['confirmation_count']),
      resolvedCount: toInt(map['resolved_count']),
      isCommunityVerified: (map['is_community_verified'] as bool?) ?? false,
      assignedDepartment: AdminDepartment.fromWire(
        map['assigned_department'] as String?,
      ),
      assignedTo: map['assigned_to'] as String?,
      acknowledgedAt: toDateTimeOrNull(map['acknowledged_at']),
      resolvedAt: toDateTimeOrNull(map['resolved_at']),
      resolutionNotes: map['resolution_notes'] as String?,
      resolutionPhoto: map['resolution_photo'] as String?,
      createdAt: toDateTimeOrNull(map['created_at']) ?? DateTime.now(),
      updatedAt: toDateTimeOrNull(map['updated_at']),
    );
  }

  /// Columns the app writes on insert. Server-managed fields (location,
  /// assigned_department, status, counts, timestamps) are intentionally omitted.
  Map<String, dynamic> toInsertMap() => {
    'user_id': userId,
    'category': category.wire,
    'severity': severity.wire,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    'lat': lat,
    'lng': lng,
    if (address != null) 'address': address,
    if (city != null) 'city': city,
    if (ward != null) 'ward': ward,
    'source': source,
    if (detectionType != null) 'detection_type': detectionType!.wire,
    if (evidencePackage != null) 'evidence_package': evidencePackage!.toMap(),
    if (evidenceHash != null) 'evidence_hash': evidenceHash,
    if (photoUrls != null) 'photo_urls': photoUrls,
  };
}
