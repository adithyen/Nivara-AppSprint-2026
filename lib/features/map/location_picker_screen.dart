import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/constants.dart';
import '../../core/services/location_service.dart';
import '../../core/services/ola_maps_service.dart';
import '../../core/theme.dart';

/// Result object returned by [LocationPickerScreen].
class PickedLocation {
  const PickedLocation({
    required this.lat,
    required this.lng,
    required this.address,
  });

  final double lat;
  final double lng;
  final String address;
}

/// Interactive Ola Map Location Picker with real-time Autocomplete,
/// Nearby Search, and Reverse Geocoding.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialAddress,
  });

  final double? initialLat;
  final double? initialLng;
  final String? initialAddress;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _ola = OlaMapsService.instance;
  final _locService = const LocationService();

  MapLibreMapController? _controller;
  String? _styleString;
  bool _styleLoaded = false;

  late double _currentLat;
  late double _currentLng;
  String _currentAddress = 'Locating address…';
  bool _reverseGeocoding = false;
  bool _isMoving = false;

  // Search & Autocomplete
  final _searchCtrl = TextEditingController();
  Timer? _debounceTimer;
  List<OlaPlacePrediction> _predictions = [];
  bool _searching = false;
  bool _showSuggestions = false;

  // Nearby categories
  final List<({String label, String icon, String? type})> _nearbyFilters = [
    (label: 'All Nearby', icon: '📍', type: null),
    (label: 'Hospitals', icon: '🏥', type: 'hospital'),
    (label: 'Police', icon: '👮', type: 'police'),
    (label: 'Transit', icon: '🚌', type: 'transit_station'),
    (label: 'Govt Offices', icon: '🏛️', type: 'local_government_office'),
  ];
  int _selectedFilterIdx = 0;
  List<OlaPlacePrediction> _nearbyPlaces = [];
  bool _loadingNearby = false;

  @override
  void initState() {
    super.initState();
    _currentLat = widget.initialLat ?? kDefaultLat;
    _currentLng = widget.initialLng ?? kDefaultLng;
    if (widget.initialAddress != null && widget.initialAddress!.isNotEmpty) {
      _currentAddress = widget.initialAddress!;
    }
    _loadStyle();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStyle() async {
    final style = await _ola.getAuthenticatedVectorStyleJson();
    if (mounted) {
      setState(() {
        _styleString = style ?? _darkRasterFallback();
        _styleLoaded = true;
      });
    }
  }

  String _darkRasterFallback() => jsonEncode({
    'version': 8,
    'name': 'nivara-dark',
    'sources': {
      'dark': {
        'type': 'raster',
        'tiles': [kDarkRasterTileUrl],
        'tileSize': 256,
      },
    },
    'layers': [
      {'id': 'dark-layer', 'type': 'raster', 'source': 'dark'},
    ],
  });

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    if (widget.initialAddress == null) {
      _resolveAddress(_currentLat, _currentLng);
    }
    _loadNearbyPlaces();
  }

  void _onCameraIdle() {
    final target = _controller?.cameraPosition?.target;
    if (target != null) {
      _currentLat = target.latitude;
      _currentLng = target.longitude;
    }
    if (mounted) {
      setState(() => _isMoving = false);
      _resolveAddress(_currentLat, _currentLng);
      _loadNearbyPlaces();
    }
  }

  Future<void> _resolveAddress(double lat, double lng) async {
    if (_reverseGeocoding) return;
    setState(() => _reverseGeocoding = true);
    final addr = await _ola.reverseGeocode(lat: lat, lng: lng);
    if (!mounted) return;
    setState(() {
      _reverseGeocoding = false;
      _currentAddress = addr ??
          'Location at ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    });
  }

  // ── Autocomplete Search ───────────────────────────────────────────────────

  void _onSearchChanged(String text) {
    _debounceTimer?.cancel();
    if (text.trim().isEmpty) {
      setState(() {
        _predictions = [];
        _showSuggestions = false;
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final results = await _ola.autocomplete(
        text,
        lat: _currentLat,
        lng: _currentLng,
      );
      if (!mounted) return;
      setState(() {
        _predictions = results;
        _showSuggestions = results.isNotEmpty;
        _searching = false;
      });
    });
  }

  Future<void> _selectPrediction(OlaPlacePrediction p) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _searchCtrl.text = p.mainText ?? p.description;
      _showSuggestions = false;
    });

    double? lat = p.lat;
    double? lng = p.lng;
    String addr = p.description;

    if (lat == null || lng == null) {
      final details = await _ola.getPlaceDetails(p.placeId);
      if (details != null) {
        lat = details.lat;
        lng = details.lng;
        addr = details.formattedAddress.isNotEmpty
            ? details.formattedAddress
            : details.name;
      }
    }

    if (lat != null && lng != null) {
      _currentLat = lat;
      _currentLng = lng;
      _currentAddress = addr;
      await _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(lat, lng), zoom: 16.5),
        ),
      );
    }
  }

  // ── Nearby POI Search ─────────────────────────────────────────────────────

  Future<void> _loadNearbyPlaces() async {
    final filter = _nearbyFilters[_selectedFilterIdx];
    setState(() => _loadingNearby = true);
    final places = await _ola.nearbySearch(
      lat: _currentLat,
      lng: _currentLng,
      types: filter.type,
      radius: 2000,
    );
    if (!mounted) return;
    setState(() {
      _nearbyPlaces = places;
      _loadingNearby = false;
    });
  }

  Future<void> _selectNearbyPlace(OlaPlacePrediction p) async {
    if (p.lat != null && p.lng != null) {
      _currentLat = p.lat!;
      _currentLng = p.lng!;
      _currentAddress = p.description;
      await _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(p.lat!, p.lng!), zoom: 16.5),
        ),
      );
    }
  }

  // ── GPS Recenter ──────────────────────────────────────────────────────────

  Future<void> _goToMyLocation() async {
    final perm = await _locService.ensurePermission();
    if (!_locService.isGranted(perm)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required.')),
        );
      }
      return;
    }
    final pos = await _locService.current();
    if (pos != null) {
      _currentLat = pos.latitude;
      _currentLng = pos.longitude;
      await _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(pos.latitude, pos.longitude),
            zoom: 16.5,
          ),
        ),
      );
    }
  }

  void _confirm() {
    Navigator.of(context).pop(
      PickedLocation(
        lat: _currentLat,
        lng: _currentLng,
        address: _currentAddress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. Ola Vector Map with Style1-Dark
          if (_styleLoaded && _styleString != null)
            MapLibreMap(
              styleString: _styleString!,
              initialCameraPosition: CameraPosition(
                target: LatLng(_currentLat, _currentLng),
                zoom: 15.0,
              ),
              onMapCreated: _onMapCreated,
              onCameraIdle: _onCameraIdle,
              trackCameraPosition: true,
              myLocationEnabled: false,
            )
          else
            const Center(child: CircularProgressIndicator()),

          // Camera move detection layer
          Positioned.fill(
            child: Listener(
              onPointerDown: (_) => setState(() => _isMoving = true),
              behavior: HitTestBehavior.translucent,
            ),
          ),

          // 2. Animated Center Pin Marker
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 150),
                offset: _isMoving ? const Offset(0, -0.2) : Offset.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: NivaraColors.danger,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    Container(
                      width: 4,
                      height: 10,
                      color: NivaraColors.danger,
                    ),
                    Container(
                      width: 10,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Top Floating App Bar & Search Input
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              hintText: 'Search place, road or landmark…',
                              hintStyle: TextStyle(color: scheme.outline),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        if (_searching)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (_searchCtrl.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onSearchChanged('');
                            },
                          ),
                      ],
                    ),
                  ),

                  // Autocomplete dropdown suggestions
                  if (_showSuggestions && _predictions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      constraints: const BoxConstraints(maxHeight: 240),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _predictions.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 48),
                        itemBuilder: (context, i) {
                          final p = _predictions[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.location_on_outlined,
                              size: 20,
                              color: NivaraColors.primary,
                            ),
                            title: Text(
                              p.mainText ?? p.description,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: p.secondaryText != null
                                ? Text(
                                    p.secondaryText!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                            onTap: () => _selectPrediction(p),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 4. GPS Recenter FAB
          Positioned(
            right: 16,
            bottom: 230,
            child: FloatingActionButton.small(
              heroTag: 'recenter_picker',
              backgroundColor: scheme.surfaceContainerHigh,
              onPressed: _goToMyLocation,
              child: const Icon(Icons.my_location, color: NivaraColors.primary),
            ),
          ),

          // 5. Bottom Location Card with Nearby Places & Confirm Button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nearby search filter category chips
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _nearbyFilters.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final f = _nearbyFilters[i];
                          final selected = _selectedFilterIdx == i;
                          return ChoiceChip(
                            label: Text('${f.icon} ${f.label}'),
                            selected: selected,
                            visualDensity: VisualDensity.compact,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                            onSelected: (_) {
                              setState(() => _selectedFilterIdx = i);
                              _loadNearbyPlaces();
                            },
                          );
                        },
                      ),
                    ),

                    // Nearby place suggestions list (if any)
                    if (_loadingNearby) ...[
                      const SizedBox(height: 8),
                      const SizedBox(
                        height: 20,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Finding nearby landmarks…', style: TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    ] else if (_nearbyPlaces.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 32,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _nearbyPlaces.take(6).length,
                          separatorBuilder: (_, _) => const SizedBox(width: 6),
                          itemBuilder: (context, i) {
                            final place = _nearbyPlaces[i];
                            return ActionChip(
                              label: Text(
                                place.mainText ?? place.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              avatar: const Icon(
                                Icons.near_me,
                                size: 14,
                                color: NivaraColors.primary,
                              ),
                              onPressed: () => _selectNearbyPlace(place),
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Resolved address & coordinates
                    Row(
                      children: [
                        const Icon(
                          Icons.place,
                          color: NivaraColors.accent,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _reverseGeocoding
                                    ? 'Updating address…'
                                    : _currentAddress,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_currentLat.toStringAsFixed(5)}, ${_currentLng.toStringAsFixed(5)}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.outline),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Confirm button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: NivaraColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _confirm,
                        icon: const Icon(Icons.check),
                        label: const Text(
                          'Confirm Location',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
