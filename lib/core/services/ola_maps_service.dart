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
  });

  final String placeId;
  final String name;
  final String formattedAddress;
  final double lat;
  final double lng;
  final List<String> types;

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

    return OlaPlaceDetails(
      placeId: (result['place_id'] as String?) ?? '',
      name: (result['name'] as String?) ?? '',
      formattedAddress: (result['formatted_address'] as String?) ?? '',
      lat: (loc?['lat'] as num?)?.toDouble() ?? kDefaultLat,
      lng: (loc?['lng'] as num?)?.toDouble() ?? kDefaultLng,
      types: typesList,
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
      'https://api.olamaps.io/styleEditor/v1/styleEdit/styles/1a5115aa-26c8-4e8b-8433-0e2858238ca7/Style1-Dark';

  String get darkStyleUrl {
    final configured = dotenv.env['OLA_MAPS_DARK_STYLE_URL']?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return kDefaultDarkStyleUrl;
  }

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

  // ── 3. Place Details API ──────────────────────────────────────────────────

  /// Fetches exact coordinates and full address for a given Ola [placeId].
  Future<OlaPlaceDetails?> getPlaceDetails(String placeId) async {
    final key = apiKey;
    if (key == null || placeId.trim().isEmpty) return null;

    try {
      final uri = Uri.parse('$_baseUrl/places/v1/details').replace(
        queryParameters: {
          'place_id': placeId.trim(),
          'api_key': key,
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      return OlaPlaceDetails.fromJson(data);
    } catch (e) {
      _log.error('OLA', 'Place details exception: $e');
      return null;
    }
  }

  // ── 4. Nearby Search API ──────────────────────────────────────────────────

  /// Searches for nearby venues, transit, hospitals, civic offices around [lat], [lng].
  Future<List<OlaPlacePrediction>> nearbySearch({
    required double lat,
    required double lng,
    String? types,
    double radius = 3000,
    String layers = 'venue,address',
  }) async {
    final key = apiKey;
    if (key == null) return [];

    try {
      final params = <String, String>{
        'location': '$lat,$lng',
        'radius': radius.toInt().toString(),
        'layers': layers,
        'api_key': key,
      };
      if (types != null && types.isNotEmpty) {
        params['types'] = types;
      }

      final uri = Uri.parse('$_baseUrl/places/v1/nearbysearch')
          .replace(queryParameters: params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
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
