import '../core/utils.dart';
import 'enums.dart';

/// A row of `user_profiles`. Carries the [role] that gates the admin side.
class UserProfile {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? phone;
  final String? city;
  final String? ward;

  final UserRole role;
  final AdminDepartment? department;
  final String? jurisdictionCity;
  final String? jurisdictionWard;

  final int civicScore;
  final int reportsCount;
  final int findsCount;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserProfile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.phone,
    this.city,
    this.ward,
    this.role = UserRole.citizen,
    this.department,
    this.jurisdictionCity,
    this.jurisdictionWard,
    this.civicScore = 0,
    this.reportsCount = 0,
    this.findsCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  bool get isAdmin =>
      role == UserRole.admin || role == UserRole.superadmin;
  bool get isSuperadmin => role == UserRole.superadmin;

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
        id: map['id'] as String,
        displayName: (map['display_name'] as String?) ?? 'Citizen',
        avatarUrl: map['avatar_url'] as String?,
        phone: map['phone'] as String?,
        city: map['city'] as String?,
        ward: map['ward'] as String?,
        role: UserRole.fromWire(map['role'] as String?),
        department: AdminDepartment.fromWire(map['department'] as String?),
        jurisdictionCity: map['jurisdiction_city'] as String?,
        jurisdictionWard: map['jurisdiction_ward'] as String?,
        civicScore: toInt(map['civic_score']),
        reportsCount: toInt(map['reports_count']),
        findsCount: toInt(map['finds_count']),
        createdAt: toDateTimeOrNull(map['created_at']),
        updatedAt: toDateTimeOrNull(map['updated_at']),
      );

  /// Only the columns a user may write to their own profile. Role/department
  /// changes go through the `set_user_role` RPC, never a direct update.
  Map<String, dynamic> toUpdateMap() => {
        'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (phone != null) 'phone': phone,
        if (city != null) 'city': city,
        if (ward != null) 'ward': ward,
      };

  UserProfile copyWith({
    String? displayName,
    String? avatarUrl,
    String? phone,
    String? city,
    String? ward,
  }) =>
      UserProfile(
        id: id,
        displayName: displayName ?? this.displayName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        phone: phone ?? this.phone,
        city: city ?? this.city,
        ward: ward ?? this.ward,
        role: role,
        department: department,
        jurisdictionCity: jurisdictionCity,
        jurisdictionWard: jurisdictionWard,
        civicScore: civicScore,
        reportsCount: reportsCount,
        findsCount: findsCount,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
