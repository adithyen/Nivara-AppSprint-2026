import '../core/utils.dart';
import 'enums.dart';

/// A lost or found entry — a row of `lf_items`. The DB fills `location` and
/// `updated_at` via trigger; `expires_at` defaults to +30 days.
class LFItem {
  final String id;
  final String userId;
  final LFItemType itemType;
  final LFCategory category;
  final String title;
  final String description;
  final List<String>? photoUrls;

  final double lat;
  final double lng;
  final String? locationLabel;

  /// The date the item was lost/found (DATE column, no time component).
  final DateTime eventDate;

  /// How the counterpart should reach this user — one of [LFContactMethod]'s
  /// wire values (PHONE|WHATSAPP|EMAIL|TELEGRAM|INSTAGRAM). Legacy rows may
  /// hold 'INAPP'.
  final String contactMethod;

  /// The contact string itself: a phone number, email, or @username depending
  /// on [contactMethod]. Stored in `contact_value` (legacy `contact_phone`).
  final String? contactValue;
  final int? rewardAmount;

  /// 'ACTIVE' | 'MATCHED' | 'RESOLVED' | 'EXPIRED'.
  final String status;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const LFItem({
    required this.id,
    required this.userId,
    required this.itemType,
    required this.category,
    required this.title,
    required this.description,
    this.photoUrls,
    required this.lat,
    required this.lng,
    this.locationLabel,
    required this.eventDate,
    this.contactMethod = 'PHONE',
    this.contactValue,
    this.rewardAmount,
    this.status = 'ACTIVE',
    this.expiresAt,
    this.createdAt,
    this.updatedAt,
  });

  bool get isLost => itemType == LFItemType.lost;
  bool get isFound => itemType == LFItemType.found;

  /// The typed contact method, parsed from the wire string.
  LFContactMethod get contactMethodEnum =>
      LFContactMethod.fromWire(contactMethod);

  /// True when there's an actual contact string to act on.
  bool get hasContact =>
      contactValue != null && contactValue!.trim().isNotEmpty;

  factory LFItem.fromMap(Map<String, dynamic> map) => LFItem(
    id: map['id'] as String,
    userId: map['user_id'] as String,
    itemType: LFItemType.fromWire(map['item_type'] as String?),
    category: LFCategory.fromWire(map['category'] as String?),
    title: (map['title'] as String?) ?? '',
    description: (map['description'] as String?) ?? '',
    photoUrls: toStringListOrNull(map['photo_urls']),
    lat: toDouble(map['lat']),
    lng: toDouble(map['lng']),
    locationLabel: map['location_label'] as String?,
    eventDate: toDateTimeOrNull(map['event_date']) ?? DateTime.now(),
    contactMethod: (map['contact_method'] as String?) ?? 'PHONE',
    // Prefer the new generic column; fall back to legacy contact_phone.
    contactValue:
        (map['contact_value'] as String?) ?? (map['contact_phone'] as String?),
    rewardAmount: map['reward_amount'] == null
        ? null
        : toInt(map['reward_amount']),
    status: (map['status'] as String?) ?? 'ACTIVE',
    expiresAt: toDateTimeOrNull(map['expires_at']),
    createdAt: toDateTimeOrNull(map['created_at']),
    updatedAt: toDateTimeOrNull(map['updated_at']),
  );

  /// Columns the app writes on insert. `event_date` is sent as an ISO date
  /// (yyyy-MM-dd) to match the DATE column.
  Map<String, dynamic> toInsertMap() => {
    'user_id': userId,
    'item_type': itemType.wire,
    'category': category.wire,
    'title': title,
    'description': description,
    if (photoUrls != null) 'photo_urls': photoUrls,
    'lat': lat,
    'lng': lng,
    if (locationLabel != null) 'location_label': locationLabel,
    'event_date': eventDate.toIso8601String().substring(0, 10),
    'contact_method': contactMethod,
    if (contactValue != null) 'contact_value': contactValue,
    if (rewardAmount != null) 'reward_amount': rewardAmount,
  };
}
