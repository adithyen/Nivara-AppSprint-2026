import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import 'debug_logger.dart';

/// Representation of an Autocomplete or Nearby Search prediction from Ola Maps.
class OlaPlacePrediction {
  const OlaPlacePrediction({
    required this.placeId,
    required this.description,
    this.mainText,
    this.secondaryText,
    this.lat,
    this.lng,
    this.types = const [],
  });

  final String placeId;
  final String description;
  final String? mainText;
  final String? secondaryText;
  final double? lat;
  final double? lng;
  final List<String> types;

  factory OlaPlacePrediction.fromJson(Map<String, dynamic> json) {
    final struct = json['structured_formatting'] as Map<String, dynamic>?;
    final geom = json['geometry'] as Map<String, dynamic>?;
    final loc = geom?['location'] as Map<String, dynamic>?;

    double? lat;
    double? lng;
    if (loc != null) {
      lat = (loc['lat'] as num?)?.toDouble();
      lng = (loc['lng'] as num?)?.toDouble();
    }

    final typesList = <String>[];
    if (json['types'] is List) {
      for (final t in json['types'] as List) {
        if (t != null) typesList.add(t.toString());
      }
    }

    return OlaPlacePrediction(
      placeId: (json['place_id'] as String?) ?? '',
      description: (json['description'] as String?) ??
          (json['name'] as String?) ??
          (json['formatted_address'] as String?) ??
          '',
      mainText: struct?['main_text'] as String? ?? (json['name'] as String?),
      secondaryText: struct?['secondary_text'] as String?,
      lat: lat,
      lng: lng,
      types: typesList,
    );
  }
}

/// Detailed place metadata retrieved via Ola Place Details API.
class OlaPlaceDetails {
  const OlaPlaceDetails({
    required this.placeId,
    required this.name,
    required this.formattedAddress,
    required this.lat,
    required this.lng,
    this.types = const [],
    this.rating,
    this.userRatingsTotal,
    this.phoneNumber,
    this.website,
    this.openNow,
    this.weekdayText = const [],
    this.photoReference,
    this.iconMaskUri,
  });

  final String placeId;
  final String name;
  final String formattedAddress;
  final double lat;
  final double lng;
  final List<String> types;
  final double? rating;
  final int? userRatingsTotal;
  final String? phoneNumber;
  final String? website;
  final bool? openNow;
  final List<String> weekdayText;
  final String? photoReference;
  final String? iconMaskUri;

  factory OlaPlaceDetails.fromJson(Map<String, dynamic> json) {
    final result = (json['result'] as Map<String, dynamic>?) ?? json;
    final geom = result['geometry'] as Map<String, dynamic>?;
    final loc = geom?['location'] as Map<String, dynamic>?;

    final typesList = <String>[];
    if (result['types'] is List) {
      for (final t in result['types'] as List) {
        if (t != null) typesList.add(t.toString());
      }
    }

    final openingHours = result['opening_hours'] as Map<String, dynamic>?;
    final weekdayList = <String>[];
    if (openingHours?['weekday_text'] is List) {
      for (final w in openingHours!['weekday_text'] as List) {
        if (w != null) weekdayList.add(w.toString());
      }
    }

    String? photoRef;
    if (result['photos'] is List && (result['photos'] as List).isNotEmpty) {
      final firstPhoto = (result['photos'] as List).first;
      if (firstPhoto is Map<String, dynamic>) {
        photoRef = firstPhoto['photo_reference'] as String?;
      }
    }

    final phone = (result['formatted_phone_number'] as String?)?.trim();
    final intlPhone = (result['international_phone_number'] as String?)?.trim();
    final effectivePhone = (phone != null && phone.isNotEmpty && phone != 'NA')
        ? phone
        : (intlPhone != null && intlPhone.isNotEmpty && intlPhone != 'NA' ? intlPhone : null);

    final site = (result['website'] as String?)?.trim();
    final effectiveSite = (site != null && site.isNotEmpty && site != 'NA') ? site : null;

    final rateNum = result['rating'] as num?;
    final rate = (rateNum != null && rateNum > 0) ? rateNum.toDouble() : null;

    final totalReviews = (result['user_ratings_total'] as num?)?.toInt();

    final iconUri = (result['icon_mask_base_uri'] as String?)?.trim();

    return OlaPlaceDetails(
      placeId: (result['place_id'] as String?) ?? '',
      name: (result['name'] as String?) ?? '',
      formattedAddress: (result['formatted_address'] as String?) ?? '',
      lat: (loc?['lat'] as num?)?.toDouble() ?? kDefaultLat,
      lng: (loc?['lng'] as num?)?.toDouble() ?? kDefaultLng,
      types: typesList,
      rating: rate,
      userRatingsTotal: totalReviews,
      phoneNumber: effectivePhone,
      website: effectiveSite,
      openNow: openingHours?['open_now'] as bool?,
      weekdayText: weekdayList,
      photoReference: photoRef,
      iconMaskUri: (iconUri != null && iconUri.isNotEmpty && iconUri != 'NA') ? iconUri : null,
    );
  }
}

/// Complete Client for Ola Krutrim Maps REST APIs & Style Engine.
class OlaMapsService {
  OlaMapsService._();
  static final instance = OlaMapsService._();

  static const String _baseUrl = 'https://api.olamaps.io';
  static final _log = DebugLogger.instance;

  String? get apiKey {
    final key = dotenv.env['OLA_MAPS_API_KEY']?.trim();
    return (key != null && key.isNotEmpty && !key.startsWith('your-'))
        ? key
        : null;
  }

  bool get isConfigured => apiKey != null;

  static const String kDefaultDarkStyleUrl =
      'https://api.olamaps.io/tiles/vector/v1/styles/default-dark-standard/style.json';

  static const String kDefaultLightStyleUrl =
      'https://api.olamaps.io/tiles/vector/v1/styles/default-light-standard/style.json';

  String get darkStyleUrl {
    final configured = dotenv.env['OLA_MAPS_DARK_STYLE_URL']?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return kDefaultDarkStyleUrl;
  }

  String get lightStyleUrl => kDefaultLightStyleUrl;

  String getStyleUrl({required bool isDark}) =>
      isDark ? darkStyleUrl : lightStyleUrl;

  // ── 1. Vector Style Resolver ──────────────────────────────────────────────

  /// Fetches the Ola custom or standard dark style json and dynamically signs all sub-urls
  /// (tiles, sprites, glyphs) with the API key so `maplibre_gl` / `OlaMapView` can render it
  /// without unauthenticated 403 / blank map issues.
  ///
  /// Returns a JSON string ready for `MapLibreMap(styleString: ...)` or null on failure.
  Future<String?> getAuthenticatedVectorStyleJson({
    String? customStyleUrl,
    String styleName = 'Style1-Dark',
  }) async {
    final key = apiKey;
    if (key == null) {
      _log.log('OLA', 'No API key configured for Ola Maps');
      return null;
    }

    try {
      final targetUrl = customStyleUrl ?? darkStyleUrl;
      final uri = Uri.parse(
        targetUrl.startsWith('http')
            ? _appendKey(targetUrl, key)
            : '$_baseUrl/tiles/vector/v1/styles/$styleName/style.json?api_key=$key',
      );

      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        _log.error('OLA', 'Failed to fetch style: HTTP ${resp.statusCode}');
        return null;
      }

      final Map<String, dynamic> styleMap =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;

      // 1. Inject API key into sprite
      if (styleMap.containsKey('sprite') && styleMap['sprite'] is String) {
        final spriteUrl = styleMap['sprite'] as String;
        styleMap['sprite'] = _appendKey(spriteUrl, key);
      }

      // 2. Inject API key into glyphs (font PBFs)
      if (styleMap.containsKey('glyphs') && styleMap['glyphs'] is String) {
        final glyphsUrl = styleMap['glyphs'] as String;
        styleMap['glyphs'] = _appendKey(glyphsUrl, key);
      }

      // 3. Inject API key into sources (vector tiles / raster tiles / tilejson)
      if (styleMap.containsKey('sources') && styleMap['sources'] is Map) {
        final sources = styleMap['sources'] as Map<String, dynamic>;
        for (final entry in sources.entries) {
          final src = entry.value;
          if (src is Map<String, dynamic>) {
            if (src.containsKey('url') && src['url'] is String) {
              src['url'] = _appendKey(src['url'] as String, key);
            }
            if (src.containsKey('tiles') && src['tiles'] is List) {
              final tiles = src['tiles'] as List;
              src['tiles'] = tiles
                  .map((t) => t is String ? _appendKey(t, key) : t)
                  .toList();
            }
          }
        }
      }

      final injectedJson = jsonEncode(styleMap);
      _log.log('OLA', 'Successfully constructed authenticated Ola Dark vector style (${styleMap["name"]})');
      return injectedJson;
    } catch (e, st) {
      _log.error('OLA', 'Error building authenticated style: $e', st);
      return null;
    }
  }

  // ── 2. Autocomplete Places API ────────────────────────────────────────────

  /// Search places by input query with optional bias around [lat], [lng] and [radius] in metres.
  Future<List<OlaPlacePrediction>> autocomplete(
    String input, {
    double? lat,
    double? lng,
    double radius = 50000,
  }) async {
    final key = apiKey;
    final trimmed = input.trim();
    if (key == null || trimmed.isEmpty) return [];

    try {
      final params = <String, String>{
        'input': trimmed,
        'api_key': key,
      };
      if (lat != null && lng != null) {
        params['location'] = '$lat,$lng';
        params['radius'] = radius.toInt().toString();
      }

      final uri = Uri.parse('$_baseUrl/places/v1/autocomplete')
          .replace(queryParameters: params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) {
        _log.error('OLA', 'Autocomplete HTTP ${resp.statusCode}: ${resp.body}');
        return [];
      }

      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final list = (data['predictions'] as List?) ?? [];
      return list
          .map((item) => OlaPlacePrediction.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _log.error('OLA', 'Autocomplete exception: $e');
      return [];
    }
  }

  // ── 3. Place Details & Advanced Place Details API ─────────────────────────

  /// Fetches structured metadata, geometry and operational fields for an Ola [placeId].
  /// If [advanced] is true, queries `/places/v1/details/advanced` for deeper POI attributes.
  Future<OlaPlaceDetails?> getPlaceDetails(
    String placeId, {
    bool advanced = true,
  }) async {
    final key = apiKey;
    if (key == null || placeId.trim().isEmpty) return null;

    try {
      final endpoint = advanced
          ? '$_baseUrl/places/v1/details/advanced'
          : '$_baseUrl/places/v1/details';

      final uri = Uri.parse(endpoint).replace(
        queryParameters: {
          'place_id': placeId.trim(),
          'api_key': key,
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        if (advanced) {
          // Fallback to standard details
          return getPlaceDetails(placeId, advanced: false);
        }
        return null;
      }

      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      return OlaPlaceDetails.fromJson(data);
    } catch (e) {
      _log.error('OLA', 'Place details exception: $e');
      if (advanced) return getPlaceDetails(placeId, advanced: false);
      return null;
    }
  }

  /// Builds the authenticated image URL for an Ola Places [photoReference].
  String? getPhotoUrl(String? photoReference) {
    final key = apiKey;
    if (key == null || photoReference == null || photoReference.trim().isEmpty) {
      return null;
    }
    return '$_baseUrl/places/v1/photo?photo_reference=${Uri.encodeComponent(photoReference.trim())}&api_key=$key';
  }

  // ── 4. Nearby Search API ──────────────────────────────────────────────────

  /// Searches for nearby venues, emergency facilities, transit, hospitals, civic offices around [lat], [lng].
  Future<List<OlaPlacePrediction>> nearbySearch({
    required double lat,
    required double lng,
    String? types,
    double radius = 4000,
    String layers = 'venue',
    bool advanced = false,
  }) async {
    final key = apiKey;
    if (key == null) return [];

    try {
      final endpoint = advanced
          ? '$_baseUrl/places/v1/nearbysearch/advanced'
          : '$_baseUrl/places/v1/nearbysearch';

      final params = <String, String>{
        'location': '$lat,$lng',
        'radius': radius.toInt().toString(),
        'layers': layers,
        'api_key': key,
      };
      if (types != null && types.isNotEmpty) {
        params['types'] = types;
      }

      final uri = Uri.parse(endpoint).replace(queryParameters: params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        _log.error('OLA', 'Nearby search HTTP ${resp.statusCode}: ${resp.body}');
        return [];
      }

      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final list = (data['predictions'] as List?) ?? (data['results'] as List?) ?? [];
      return list
          .map((item) => OlaPlacePrediction.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _log.error('OLA', 'Nearby search exception: $e');
      return [];
    }
  }

  // ── 5. Reverse Geocoding API ──────────────────────────────────────────────

  /// Converts [lat] & [lng] coordinates into a readable human address string.
  Future<String?> reverseGeocode({
    required double lat,
    required double lng,
  }) async {
    final key = apiKey;
    if (key == null) return null;

    try {
      final uri = Uri.parse('$_baseUrl/places/v1/reverse-geocode').replace(
        queryParameters: {
          'latlng': '$lat,$lng',
          'api_key': key,
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final results = (data['results'] as List?) ?? [];
      if (results.isNotEmpty) {
        final first = results.first as Map<String, dynamic>;
        return (first['formatted_address'] as String?) ??
            (first['name'] as String?);
      }
      return null;
    } catch (e) {
      _log.error('OLA', 'Reverse geocode exception: $e');
      return null;
    }
  }

  // ── 6. Forward Geocoding API ──────────────────────────────────────────────

  /// Converts an address text string into coordinates.
  Future<Map<String, dynamic>?> geocode(String address) async {
    final key = apiKey;
    final trimmed = address.trim();
    if (key == null || trimmed.isEmpty) return null;

    try {
      final uri = Uri.parse('$_baseUrl/places/v1/geocode').replace(
        queryParameters: {
          'address': trimmed,
          'api_key': key,
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final results = (data['geocodingResults'] as List?) ??
          (data['results'] as List?) ??
          [];
      if (results.isNotEmpty) {
        final first = results.first as Map<String, dynamic>;
        final geom = first['geometry'] as Map<String, dynamic>?;
        final loc = geom?['location'] as Map<String, dynamic>?;
        if (loc != null) {
          return {
            'lat': (loc['lat'] as num).toDouble(),
            'lng': (loc['lng'] as num).toDouble(),
            'formatted_address': first['formatted_address'],
          };
        }
      }
      return null;
    } catch (e) {
      _log.error('OLA', 'Geocode exception: $e');
      return null;
    }
  }

  // ── Internal Helpers ──────────────────────────────────────────────────────

  String _appendKey(String url, String key) {
    if (url.contains('api_key=')) return url;
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}api_key=$key';
  }
}
