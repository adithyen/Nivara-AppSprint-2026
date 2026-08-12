/// Domain enums mirroring the Postgres enum types in
/// `supabase/migrations/0001_init.sql`.
///
/// Each value carries its [wire] string (the exact uppercase value the DB
/// stores) and a human [label]. Parse DB rows with `X.fromWire(row['col'])`;
/// send to the DB with `value.wire`. Kept free of any Flutter import so models
/// stay unit-testable.
library;

// ── Roles & departments ─────────────────────────────────────────────────────
enum UserRole {
  citizen('CITIZEN', 'Citizen'),
  worker('WORKER', 'Field Worker'),
  admin('ADMIN', 'Administrator'),
  superadmin('SUPERADMIN', 'Super Admin');

  final String wire;
  final String label;
  const UserRole(this.wire, this.label);

  static UserRole fromWire(String? w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => UserRole.citizen);
}

enum AdminDepartment {
  general('GENERAL', 'General'),
  roads('ROADS', 'Roads'),
  sanitation('SANITATION', 'Sanitation'),
  water('WATER', 'Water'),
  electricity('ELECTRICITY', 'Electricity'),
  parks('PARKS', 'Parks'),
  animals('ANIMALS', 'Animals'),
  enforcement('ENFORCEMENT', 'Enforcement');

  final String wire;
  final String label;
  const AdminDepartment(this.wire, this.label);

  static AdminDepartment? fromWire(String? w) {
    if (w == null) return null;
    for (final e in values) {
      if (e.wire == w) return e;
    }
    return null;
  }
}

// ── Reports ─────────────────────────────────────────────────────────────────
enum ReportCategory {
  pothole('POTHOLE', 'Pothole'),
  brokenFootpath('BROKEN_FOOTPATH', 'Broken Footpath'),
  openManhole('OPEN_MANHOLE', 'Open Manhole'),
  fallenTree('FALLEN_TREE', 'Fallen Tree'),
  waterlogging('WATERLOGGING', 'Waterlogging'),
  roadSign('ROAD_SIGN', 'Road Sign'),
  garbage('GARBAGE', 'Garbage'),
  blockedDrain('BLOCKED_DRAIN', 'Blocked Drain'),
  sewage('SEWAGE', 'Sewage'),
  streetLight('STREET_LIGHT', 'Street Light'),
  damagedPole('DAMAGED_POLE', 'Damaged Pole'),
  powerIssue('POWER_ISSUE', 'Power Issue'),
  waterSupply('WATER_SUPPLY', 'Water Supply'),
  pipeLeak('PIPE_LEAK', 'Pipe Leak'),
  encroachment('ENCROACHMENT', 'Encroachment'),
  brokenProperty('BROKEN_PROPERTY', 'Broken Property'),
  strayAnimals('STRAY_ANIMALS', 'Stray Animals'),
  noise('NOISE', 'Noise'),
  other('OTHER', 'Other');

  final String wire;
  final String label;
  const ReportCategory(this.wire, this.label);

  static ReportCategory fromWire(String? w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => ReportCategory.other);
}

enum ReportStatus {
  submitted('SUBMITTED', 'Submitted'),
  acknowledged('ACKNOWLEDGED', 'Acknowledged'),
  inProgress('IN_PROGRESS', 'In Progress'),
  resolved('RESOLVED', 'Resolved'),
  closed('CLOSED', 'Closed'),
  duplicate('DUPLICATE', 'Duplicate');

  final String wire;
  final String label;
  const ReportStatus(this.wire, this.label);

  static ReportStatus fromWire(String? w) => values.firstWhere(
    (e) => e.wire == w,
    orElse: () => ReportStatus.submitted,
  );
}

enum Severity {
  low('LOW', 'Low'),
  medium('MEDIUM', 'Medium'),
  high('HIGH', 'High'),
  emergency('EMERGENCY', 'Emergency');

  final String wire;
  final String label;
  const Severity(this.wire, this.label);

  static Severity fromWire(String? w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => Severity.medium);
}

enum DetectionType {
  pothole('POTHOLE', 'Pothole'),
  speedBreaker('SPEED_BREAKER', 'Speed Breaker'),
  badRoad('BAD_ROAD', 'Bad Road'),
  manual('MANUAL', 'Manual');

  final String wire;
  final String label;
  const DetectionType(this.wire, this.label);

  static DetectionType? fromWire(String? w) {
    if (w == null) return null;
    for (final e in values) {
      if (e.wire == w) return e;
    }
    return null;
  }
}

// ── Lost & Found ────────────────────────────────────────────────────────────
enum LFCategory {
  aadhaar('AADHAAR', 'Aadhaar'),
  panCard('PAN_CARD', 'PAN Card'),
  drivingLicence('DRIVING_LICENCE', 'Driving Licence'),
  passport('PASSPORT', 'Passport'),
  otherDocument('OTHER_DOCUMENT', 'Other Document'),
  mobilePhone('MOBILE_PHONE', 'Mobile Phone'),
  wallet('WALLET', 'Wallet'),
  keys('KEYS', 'Keys'),
  bag('BAG', 'Bag'),
  jewellery('JEWELLERY', 'Jewellery'),
  pet('PET', 'Pet'),
  vehicle('VEHICLE', 'Vehicle'),
  other('OTHER', 'Other');

  final String wire;
  final String label;
  const LFCategory(this.wire, this.label);

  static LFCategory fromWire(String? w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => LFCategory.other);
}

enum LFItemType {
  lost('LOST', 'Lost'),
  found('FOUND', 'Found');

  final String wire;
  final String label;
  const LFItemType(this.wire, this.label);

  static LFItemType fromWire(String? w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => LFItemType.lost);
}

/// How a Lost & Found poster wants to be reached. Each maps to a one-tap deep
/// link on the viewer's side (see `features/lostfound/lf_contact.dart`):
/// phone → `tel:`, whatsapp → `wa.me/…`, email → `mailto:`,
/// telegram → `t.me/…`, instagram → `instagram.com/…`.
enum LFContactMethod {
  phone('PHONE', 'Phone'),
  whatsapp('WHATSAPP', 'WhatsApp'),
  email('EMAIL', 'Email'),
  telegram('TELEGRAM', 'Telegram'),
  instagram('INSTAGRAM', 'Instagram');

  final String wire;
  final String label;
  const LFContactMethod(this.wire, this.label);

  /// Legacy rows may carry 'INAPP'; fall back to phone so the UI stays sane.
  static LFContactMethod fromWire(String? w) => values.firstWhere(
    (e) => e.wire == w,
    orElse: () => LFContactMethod.phone,
  );
}

enum MatchStatus {
  pending('PENDING', 'Pending'),
  confirmedByFinder('CONFIRMED_BY_FINDER', 'Confirmed by Finder'),
  confirmedByBoth('CONFIRMED_BY_BOTH', 'Confirmed by Both'),
  rejected('REJECTED', 'Rejected'),
  resolved('RESOLVED', 'Resolved');

  final String wire;
  final String label;
  const MatchStatus(this.wire, this.label);

  static MatchStatus fromWire(String? w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => MatchStatus.pending);
}

/// Lifecycle of a Lost & Found claim (see `0005_lf_claims.sql`). A claimant
/// sends a PENDING claim on someone else's listing; the owner COMPLETEs it
/// (resolving both listings) or REJECTs it; the claimant may CANCEL their own.
enum LFClaimStatus {
  pending('PENDING', 'Pending'),
  completed('COMPLETED', 'Completed'),
  rejected('REJECTED', 'Rejected'),
  cancelled('CANCELLED', 'Withdrawn');

  final String wire;
  final String label;
  const LFClaimStatus(this.wire, this.label);

  static LFClaimStatus fromWire(String? w) => values.firstWhere(
    (e) => e.wire == w,
    orElse: () => LFClaimStatus.pending,
  );
}

// ── Community board ─────────────────────────────────────────────────────────
/// The four post templates on the neighbourhood Community board. Mirrors the
/// `community_post_type` Postgres enum in `0002_community.sql`.
enum CommunityPostType {
  general('GENERAL', 'Post'),
  poll('POLL', 'Poll'),
  job('JOB', 'Job / Service'),
  announcement('ANNOUNCEMENT', 'Announcement');

  final String wire;
  final String label;
  const CommunityPostType(this.wire, this.label);

  static CommunityPostType fromWire(String? w) => values.firstWhere(
    (e) => e.wire == w,
    orElse: () => CommunityPostType.general,
  );
}

/// A community post is OPEN (active) or CLOSED (the author ended it — a filled
/// job, a finished poll). Mirrors `community_post_status`.
enum CommunityPostStatus {
  open('OPEN', 'Open'),
  closed('CLOSED', 'Closed');

  final String wire;
  final String label;
  const CommunityPostStatus(this.wire, this.label);

  static CommunityPostStatus fromWire(String? w) => values.firstWhere(
    (e) => e.wire == w,
    orElse: () => CommunityPostStatus.open,
  );
}
