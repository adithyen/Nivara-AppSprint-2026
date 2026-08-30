import 'dart:math' as math;

import 'package:intl/intl.dart';

/// Great-circle distance in **metres** between two lat/lng points.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusM = 6371000.0;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusM * c;
}

double _toRad(double deg) => deg * math.pi / 180.0;

/// Human-readable distance: `340 m`, `2.4 km`.
String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000;
  return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
}

/// Localized distance, e.g. `340 മീറ്റർ അകലെ` / `340 मीटर दूर` / `340 m away`.
String formatLocalizedDistance(double meters, dynamic lang) {
  final langCode = lang.toString().split('.').last;
  final suffix = (meters < 1000)
      ? (langCode == 'ml' ? 'മീറ്റർ അകലെ' : (langCode == 'hi' ? 'मीटर दूर' : 'm away'))
      : (langCode == 'ml' ? 'കി.മീ അകലെ' : (langCode == 'hi' ? 'किमी दूर' : 'km away'));
  if (meters < 1000) return '${meters.round()} $suffix';
  final km = meters / 1000;
  return '${km.toStringAsFixed(km < 10 ? 1 : 0)} $suffix';
}

/// Absolute date/time, e.g. `12 Jul 2026, 2:34 PM`.
String formatDateTime(DateTime dt) =>
    DateFormat('d MMM y, h:mm a').format(dt.toLocal());

/// Date only, e.g. `12 Jul 2026`.
String formatDate(DateTime dt) => DateFormat('d MMM y').format(dt.toLocal());

/// Relative time, e.g. `just now`, `3h ago`, `2d ago`, else an absolute date.
String timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDate(dt);
}

/// Parse a nullable value coming from Supabase into a `double`.
double? toDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

/// Parse a Supabase value into a `double`, defaulting to [fallback].
double toDouble(dynamic v, [double fallback = 0]) =>
    toDoubleOrNull(v) ?? fallback;

/// Parse a Supabase value into an `int`, defaulting to [fallback].
int toInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

/// Parse a nullable timestamp string/DateTime from Supabase.
DateTime? toDateTimeOrNull(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

/// Parse a `List<String>` from a Supabase array column (or null).
List<String>? toStringListOrNull(dynamic v) {
  if (v == null) return null;
  if (v is List) return v.map((e) => e.toString()).toList();
  return null;
}
