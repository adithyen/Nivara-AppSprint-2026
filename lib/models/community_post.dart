import '../core/utils.dart';
import 'enums.dart';

/// A neighbourhood Community board entry — a row of `community_posts`.
///
/// Location is OPTIONAL: a post with no lat/lng is city-wide; a located post is
/// only surfaced to viewers within [visibilityRadiusKm] (enforced by the
/// `community_posts_near` RPC). [authorName] is denormalised on the row so the
/// public feed never has to read another user's (RLS-private) profile.
///
/// Poll options live in a separate table ([CommunityPollOption]); the feed
/// loads them alongside POLL posts.
class CommunityPost {
  final String id;
  final String authorId;
  final String authorName;
  final CommunityPostType type;
  final String title;
  final String? body;
  final List<String>? photoUrls;

  final double? lat;
  final double? lng;
  final String? locationLabel;

  /// How far (km) a located post stays visible. Ignored for city-wide posts.
  final double visibilityRadiusKm;

  /// Optional one-tap contact — reuses the Lost & Found wire values
  /// (PHONE|WHATSAPP|EMAIL|TELEGRAM|INSTAGRAM). See `lostfound/lf_contact.dart`.
  final String? contactMethod;
  final String? contactValue;

  final CommunityPostStatus status;
  final DateTime? validUntil;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const CommunityPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    this.type = CommunityPostType.general,
    required this.title,
    this.body,
    this.photoUrls,
    this.lat,
    this.lng,
    this.locationLabel,
    this.visibilityRadiusKm = 5,
    this.contactMethod,
    this.contactValue,
    this.status = CommunityPostStatus.open,
    this.validUntil,
    required this.createdAt,
    this.updatedAt,
  });

  bool get hasLocation => lat != null && lng != null;
  bool get isOpen => status == CommunityPostStatus.open;
  bool get isPoll => type == CommunityPostType.poll;
  bool get hasContact =>
      contactMethod != null &&
      contactValue != null &&
      contactValue!.trim().isNotEmpty;

  /// The typed contact method, or null when the author gave no contact.
  LFContactMethod? get contactMethodEnum =>
      contactMethod == null ? null : LFContactMethod.fromWire(contactMethod);

  factory CommunityPost.fromMap(Map<String, dynamic> map) => CommunityPost(
    id: map['id'] as String,
    authorId: map['author_id'] as String,
    authorName: (map['author_name'] as String?) ?? 'Citizen',
    type: CommunityPostType.fromWire(map['post_type'] as String?),
    title: (map['title'] as String?) ?? '',
    body: map['body'] as String?,
    photoUrls: toStringListOrNull(map['photo_urls']),
    lat: toDoubleOrNull(map['lat']),
    lng: toDoubleOrNull(map['lng']),
    locationLabel: map['location_label'] as String?,
    visibilityRadiusKm: toDouble(map['visibility_radius_km'], 5),
    contactMethod: map['contact_method'] as String?,
    contactValue: map['contact_value'] as String?,
    status: CommunityPostStatus.fromWire(map['status'] as String?),
    validUntil: toDateTimeOrNull(map['valid_until']),
    createdAt: toDateTimeOrNull(map['created_at']) ?? DateTime.now(),
    updatedAt: toDateTimeOrNull(map['updated_at']),
  );

  /// Columns the app writes on insert. Server-managed fields (location point,
  /// timestamps) are omitted — the trigger fills them.
  Map<String, dynamic> toInsertMap() => {
    'author_id': authorId,
    'author_name': authorName,
    'post_type': type.wire,
    'title': title,
    if (body != null) 'body': body,
    if (photoUrls != null) 'photo_urls': photoUrls,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
    if (locationLabel != null) 'location_label': locationLabel,
    'visibility_radius_km': visibilityRadiusKm,
    if (contactMethod != null) 'contact_method': contactMethod,
    if (contactValue != null) 'contact_value': contactValue,
    if (validUntil != null) 'valid_until': validUntil!.toIso8601String(),
  };
}
