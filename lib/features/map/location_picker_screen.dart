import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/services/location_service.dart';
import '../../core/services/ola_maps_service.dart';
import '../../core/widgets/ola_map_view.dart';

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

/// 2026-Level Futuristic Ola Map Location Picker with real-time Autocomplete,
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

  OlaNativeMapController? _controller;
  late double _currentLat;
  late double _currentLng;
  String _currentAddress = 'Pinpoint address…';
  bool _reverseGeocoding = false;
  bool _isMoving = false;

  // Search & Autocomplete
  final _searchCtrl = TextEditingController();
  Timer? _debounceTimer;
  List<OlaPlacePrediction> _predictions = [];
  bool _searching = false;
  bool _showSuggestions = false;

  // Nearby discovery filters
  final List<({String label, String icon, String? type})> _nearbyFilters = [
    (label: 'Nearby Landmarks', icon: '📍', type: null),
    (label: 'Hospitals', icon: '🏥', type: 'hospital'),
    (label: 'Police', icon: '👮', type: 'police'),
    (label: 'Transit', icon: '🚌', type: 'transit_station'),
    (label: 'Civic Offices', icon: '🏛️', type: 'local_government_office'),
    (label: 'Pharmacies', icon: '💊', type: 'pharmacy'),
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
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onMapReady(OlaNativeMapController controller) {
    _controller = controller;
    if (widget.initialAddress == null) {
      _resolveAddress(_currentLat, _currentLng);
    }
    _loadNearbyPlaces();
  }

  void _onCameraIdle(double? lat, double? lng) {
    if (lat != null && lng != null) {
      _currentLat = lat;
      _currentLng = lng;
    }
    if (mounted) {
      setState(() => _isMoving = false);
      _resolveAddress(_currentLat, _currentLng);
      _loadNearbyPlaces();
    }
  }

  int _geocodeSeq = 0;

  Future<void> _resolveAddress(double lat, double lng) async {
    final seq = ++_geocodeSeq;
    setState(() => _reverseGeocoding = true);
    final addr = await _ola.reverseGeocode(lat: lat, lng: lng);
    if (!mounted || seq != _geocodeSeq) return;
    setState(() {
      _reverseGeocoding = false;
      _currentAddress = addr ??
          '${lat.toStringAsFixed(5)}° N, ${lng.toStringAsFixed(5)}° E';
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
    _debounceTimer = Timer(const Duration(milliseconds: 280), () async {
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
      await _controller?.animateCamera(lat: lat, lng: lng, zoom: 16.5);
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
      radius: 2500,
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
      await _controller?.animateCamera(lat: p.lat!, lng: p.lng!, zoom: 16.5);
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
        lat: pos.latitude,
        lng: pos.longitude,
        zoom: 16.5,
      );
      _controller?.showCurrentLocation();
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
    return Scaffold(
      backgroundColor: const Color(0xFF090D12),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. Native Ola Map View
          OlaNativeMapWidget(
            initialLat: _currentLat,
            initialLng: _currentLng,
            initialZoom: 15.5,
            onMapReady: _onMapReady,
            onCameraIdle: _onCameraIdle,
            onMapClicked: (lat, lng) {
              _currentLat = lat;
              _currentLng = lng;
              _controller?.animateCamera(lat: lat, lng: lng);
            },
          ),

          // User pointer touch detection for pin bounce animation
          Positioned.fill(
            child: Listener(
              onPointerDown: (_) => setState(() => _isMoving = true),
              behavior: HitTestBehavior.translucent,
            ),
          ),

          // 2. Futuristic Animated Center Pin
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 38),
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                offset: _isMoving ? const Offset(0, -0.22) : Offset.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E676).withValues(alpha: 0.5),
                            blurRadius: 16,
                            spreadRadius: 2,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.black,
                        size: 24,
                      ),
                    ),
                    Container(
                      width: 3,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Container(
                      width: 14,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Ultra-Modern Glassmorphic Search Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF131A22).withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _searchCtrl,
                                onChanged: _onSearchChanged,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search city, landmark or road…',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            if (_searching)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF00E676),
                                  ),
                                ),
                              )
                            else if (_searchCtrl.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.close, size: 18, color: Colors.white70),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _onSearchChanged('');
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Autocomplete dropdown suggestions
                  if (_showSuggestions && _predictions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 250),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131A22).withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _predictions.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            indent: 52,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          itemBuilder: (context, i) {
                            final p = _predictions[i];
                            return ListTile(
                              dense: true,
                              leading: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E676).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.location_on,
                                  size: 16,
                                  color: Color(0xFF00E676),
                                ),
                              ),
                              title: Text(
                                p.mainText ?? p.description,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: p.secondaryText != null
                                  ? Text(
                                      p.secondaryText!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white.withValues(alpha: 0.5),
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
                    ),
                ],
              ),
            ),
          ),

          // 4. GPS Recenter Floating FAB
          Positioned(
            right: 18,
            bottom: 240,
            child: FloatingActionButton.small(
              heroTag: 'picker_recenter_2026',
              backgroundColor: const Color(0xFF151D28).withValues(alpha: 0.9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
              ),
              onPressed: _goToMyLocation,
              child: const Icon(Icons.my_location, color: Color(0xFF00E676), size: 20),
            ),
          ),

          // 5. 2026-Level Futuristic Glassmorphic Bottom Panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10161E).withValues(alpha: 0.92),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(
                      top: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 24,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Nearby search filter pills
                        SizedBox(
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _nearbyFilters.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 8),
                            itemBuilder: (context, i) {
                              final f = _nearbyFilters[i];
                              final selected = _selectedFilterIdx == i;
                              return GestureDetector(
                                onTap: () {
                                  setState(() => _selectedFilterIdx = i);
                                  _loadNearbyPlaces();
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFF00E676).withValues(alpha: 0.18)
                                        : Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: selected
                                          ? const Color(0xFF00E676).withValues(alpha: 0.7)
                                          : Colors.white.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Text(
                                    '${f.icon} ${f.label}',
                                    style: TextStyle(
                                      color: selected ? const Color(0xFF00E676) : Colors.white70,
                                      fontSize: 12,
                                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        // Nearby landmark suggestions
                        if (_loadingNearby) ...[
                          const SizedBox(height: 10),
                          const SizedBox(
                            height: 20,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF00E676),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Scanning nearby landmarks with Ola…',
                                  style: TextStyle(color: Colors.white60, fontSize: 11),
                                ),
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
                                  backgroundColor: const Color(0xFF19222D),
                                  side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                                  label: Text(
                                    place.mainText ?? place.description,
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  avatar: const Icon(
                                    Icons.near_me,
                                    size: 13,
                                    color: Color(0xFF00E676),
                                  ),
                                  onPressed: () => _selectNearbyPlace(place),
                                );
                              },
                            ),
                          ),
                        ],

                        const SizedBox(height: 14),

                        // Resolved Address & Monospace GPS Coordinates
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E676).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.place,
                                color: Color(0xFF00E676),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _reverseGeocoding
                                        ? 'Resolving address…'
                                        : _currentAddress,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${_currentLat.toStringAsFixed(5)}° N, ${_currentLng.toStringAsFixed(5)}° E',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.45),
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Futuristic Gradient Confirm Button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00E676).withValues(alpha: 0.4),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _confirm,
                              icon: const Icon(Icons.check_circle, color: Colors.black),
                              label: const Text(
                                'Confirm Selected Location',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
