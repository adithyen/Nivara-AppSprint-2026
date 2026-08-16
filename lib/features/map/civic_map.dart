import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/services/debug_logger.dart';
import '../../core/services/location_service.dart';
import '../../core/services/ola_maps_service.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/ola_map_view.dart';
import '../../models/enums.dart';
import '../../models/lf_item.dart';
import '../../models/report.dart';
import '../../router.dart';
import '../report/category_grid.dart';

/// 2026-Level Futuristic Civic Map powered by official Native Ola Maps SDK.
///
/// Features:
/// • Full native Android Ola Map rendering with Ola custom Dark vector tiles
/// • Real-time Civic & Emergency Services discovery (Hospitals, Police, Transit, Civic Offices, Pharmacies)
/// • Deep Place Details integration with direct Google Maps navigation & Turn-by-Turn routing
/// • Interactive POI Dossier Sheet with ratings, photos, operational status, direct calling & reporting
/// • Layer controls for Citizen Reports, Lost & Found items, and Service POIs
/// • Supabase Realtime synchronization with live colored marker pins
class CivicMapScreen extends ConsumerStatefulWidget {
  const CivicMapScreen({super.key});

  @override
  ConsumerState<CivicMapScreen> createState() => _CivicMapScreenState();
}

class _CivicMapScreenState extends ConsumerState<CivicMapScreen> {
  static final _log = DebugLogger.instance;
  final _ola = OlaMapsService.instance;
  final _loc = const LocationService();

  OlaNativeMapController? _controller;
  bool _mapReady = false;
  bool _locating = false;
  bool _showLog = false;

  // Active layer visibility toggles
  bool _showReportsLayer = true;
  bool _showLfLayer = true;
  bool _showNearbyPoiLayer = true;

  // Cached data
  final Map<String, Report> _reports = {};
  final Map<String, LFItem> _lfItems = {};
  StreamSubscription? _reportsSub;
  StreamSubscription? _lfSub;

  // Current map center & User location
  double _currentCenterLat = kDefaultLat;
  double _currentCenterLng = kDefaultLng;
  double? _userLat;
  double? _userLng;

  // Search & Autocomplete
  final _searchCtrl = TextEditingController();
  Timer? _debounceTimer;
  List<OlaPlacePrediction> _predictions = [];
  bool _searching = false;
  bool _showSuggestions = false;

  // Nearby Civic & Emergency Services Filters
  final List<({String label, String icon, String type, Color color, String helpline})> _nearbyServices = [
    (label: 'Hospitals', icon: '🏥', type: 'hospital', color: const Color(0xFFFF5252), helpline: '108'),
    (label: 'Police', icon: '👮', type: 'police', color: const Color(0xFF448AFF), helpline: '100'),
    (label: 'Transit & Metro', icon: '🚌', type: 'transit_station', color: const Color(0xFF00E676), helpline: '139'),
    (label: 'Pharmacies', icon: '💊', type: 'pharmacy', color: const Color(0xFFE040FB), helpline: '108'),
    (label: 'Civic Offices', icon: '🏛️', type: 'local_government_office', color: const Color(0xFFFFD700), helpline: '1913'),
    (label: 'Fire Stations', icon: '🚒', type: 'fire_station', color: const Color(0xFFFF6E40), helpline: '101'),
  ];
  int? _selectedServiceIdx;
  List<OlaPlacePrediction> _nearbyPlaces = [];
  bool _loadingNearby = false;

  // Active selected place details
  final Map<String, OlaPlaceDetails> _cachedPoiDetails = {};

  // Quick spot tap inspect
  ({double lat, double lng, String address})? _selectedSpot;

  @override
  void initState() {
    super.initState();
    _log.log('MAP', 'CivicMapScreen initState (Native Ola Map + Places)');
    _seedFromRest();
    _subscribeRealtime();
    _trackUserLocation();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    _reportsSub?.cancel();
    _lfSub?.cancel();
    super.dispose();
  }

  Future<void> _trackUserLocation() async {
    final pos = await _loc.current();
    if (pos != null && mounted) {
      setState(() {
        _userLat = pos.latitude;
        _userLng = pos.longitude;
      });
    }
  }

  // ── Realtime & REST Sync ──────────────────────────────────────────────────

  Future<void> _seedFromRest() async {
    try {
      final rows = await supabase.from(kTableReports).select();
      for (final r in rows) {
        try {
          final rep = Report.fromMap(r);
          if (rep.status != ReportStatus.resolved &&
              rep.status != ReportStatus.closed &&
              rep.status != ReportStatus.duplicate) {
            _reports[rep.id] = rep;
          }
        } catch (_) {}
      }
    } catch (e) {
      _log.error('MAP', 'reports seed failed: $e');
    }

    try {
      final rows = await supabase
          .from(kTableLfItems)
          .select()
          .eq('status', 'ACTIVE');
      for (final r in rows) {
        try {
          _lfItems[r['id'] as String] = LFItem.fromMap(r);
        } catch (_) {}
      }
    } catch (e) {
      _log.error('MAP', 'lf_items seed failed: $e');
    }

    if (_mapReady) _syncMarkersToOlaMap();
  }

  void _subscribeRealtime() {
    _reportsSub = supabase
        .from(kTableReports)
        .stream(primaryKey: ['id'])
        .listen((rows) {
          for (final r in rows) {
            try {
              final rep = Report.fromMap(r);
              if (rep.status == ReportStatus.resolved ||
                  rep.status == ReportStatus.closed ||
                  rep.status == ReportStatus.duplicate) {
                _reports.remove(rep.id);
              } else {
                _reports[rep.id] = rep;
              }
            } catch (_) {}
          }
          if (_mapReady) _syncMarkersToOlaMap();
        });

    _lfSub = supabase
        .from(kTableLfItems)
        .stream(primaryKey: ['id'])
        .listen((rows) {
          for (final r in rows) {
            try {
              final item = LFItem.fromMap(r);
              if (item.status != 'ACTIVE') {
                _lfItems.remove(item.id);
              } else {
                _lfItems[item.id] = item;
              }
            } catch (_) {}
          }
          if (_mapReady) _syncMarkersToOlaMap();
        });
  }

  Future<void> _syncMarkersToOlaMap() async {
    final c = _controller;
    if (c == null) return;

    await c.clearMarkers();

    // 1. Citizen Reports (if enabled) — Only active, with status-driven colors
    if (_showReportsLayer) {
      for (final r in _reports.values) {
        if (r.status == ReportStatus.resolved ||
            r.status == ReportStatus.closed ||
            r.status == ReportStatus.duplicate) {
          continue;
        }
        // User specification:
        // Red: Not Acknowledged (submitted)
        // Orange: Acknowledged (acknowledged, no worker yet)
        // Yellow: Workers Assigned (acknowledged + assignedTo)
        // Green: Work in Progress (inProgress)
        final color = switch (r.status) {
          ReportStatus.submitted => const Color(0xFFFF3B30),
          ReportStatus.acknowledged => (r.assignedTo != null && r.assignedTo!.isNotEmpty)
              ? const Color(0xFFFFD600)
              : const Color(0xFFFF9500),
          ReportStatus.inProgress => const Color(0xFF00E676),
          _ => const Color(0xFFFF3B30),
        };
        await c.addMarker(
          id: 'report_${r.id}',
          lat: r.lat,
          lng: r.lng,
          snippet: r.title ?? r.category.label,
          color: color,
          type: 'report',
          label: r.category.label,
        );
      }
    }

    // 2. Lost & Found Items (if enabled) — ONLY active items with distinct badges
    if (_showLfLayer) {
      for (final l in _lfItems.values) {
        if (l.status != 'ACTIVE') continue;
        final color = l.isLost ? const Color(0xFFFF6D00) : const Color(0xFF00B0FF);
        await c.addMarker(
          id: 'lf_${l.id}',
          lat: l.lat,
          lng: l.lng,
          snippet: '${l.isLost ? 'Lost' : 'Found'}: ${l.title}',
          color: color,
          type: l.isLost ? 'lost' : 'found',
          label: l.isLost ? 'LOST' : 'FOUND',
        );
      }
    }

    // 3. Nearby Service POIs (if enabled and selected)
    if (_showNearbyPoiLayer && _nearbyPlaces.isNotEmpty) {
      final activeColor = _selectedServiceIdx != null
          ? _nearbyServices[_selectedServiceIdx!].color
          : const Color(0xFF00E676);

      for (final p in _nearbyPlaces) {
        if (p.lat != null && p.lng != null) {
          await c.addMarker(
            id: 'poi_${p.placeId}',
            lat: p.lat!,
            lng: p.lng!,
            snippet: p.mainText ?? p.description,
            color: activeColor,
            type: 'poi',
          );
        }
      }
    }
  }

  static const String kDroppedPinMarkerId = '__civic_dropped_pin__';

  // ── Native Map Callbacks ──────────────────────────────────────────────────

  void _onMapReady(OlaNativeMapController controller) {
    _controller = controller;
    _mapReady = true;
    _syncMarkersToOlaMap();
    _goToMyLocation(initial: true);
  }

  void _onMarkerClicked(String markerId) {
    if (markerId == kDroppedPinMarkerId) return;

    if (markerId.startsWith('report_')) {
      final id = markerId.substring('report_'.length);
      final r = _reports[id];
      if (r != null) _showReportSheet(r);
    } else if (markerId.startsWith('lf_')) {
      final id = markerId.substring('lf_'.length);
      final l = _lfItems[id];
      if (l != null) _showLfSheet(l);
    } else if (markerId.startsWith('poi_')) {
      final placeId = markerId.substring('poi_'.length);
      _inspectPlaceById(placeId);
    }
  }

  Future<void> _onMapClicked(double lat, double lng) async {
    // 1. Check proximity to nearby POIs (within ~60 metres)
    if (_showNearbyPoiLayer && _nearbyPlaces.isNotEmpty) {
      for (final p in _nearbyPlaces) {
        if (p.lat != null && p.lng != null) {
          final dist = Geolocator.distanceBetween(lat, lng, p.lat!, p.lng!);
          if (dist <= 60) {
            _inspectPlaceById(
              p.placeId,
              fallbackName: p.mainText ?? p.description,
              fallbackLat: p.lat,
              fallbackLng: p.lng,
            );
            return;
          }
        }
      }
    }

    // 2. Check proximity to Citizen Reports
    if (_showReportsLayer && _reports.isNotEmpty) {
      for (final r in _reports.values) {
        final dist = Geolocator.distanceBetween(lat, lng, r.lat, r.lng);
        if (dist <= 60) {
          _showReportSheet(r);
          return;
        }
      }
    }

    // 3. Check proximity to Lost & Found Items
    if (_showLfLayer && _lfItems.isNotEmpty) {
      for (final l in _lfItems.values) {
        final dist = Geolocator.distanceBetween(lat, lng, l.lat, l.lng);
        if (dist <= 60) {
          _showLfSheet(l);
          return;
        }
      }
    }

    // 4. If user had an active nearby service search, dismiss it on tapping elsewhere on the map
    if (_selectedServiceIdx != null || _nearbyPlaces.isNotEmpty) {
      setState(() {
        _selectedServiceIdx = null;
        _nearbyPlaces = [];
      });
      _syncMarkersToOlaMap();
    }

    // 5. Plain map coordinate tap: Drop visual pin marker for instant user feedback!
    await _controller?.addMarker(
      id: kDroppedPinMarkerId,
      lat: lat,
      lng: lng,
      snippet: 'Selected Location',
      color: const Color(0xFF00E676),
      type: 'dropped_pin',
    );

    final addr = await _ola.reverseGeocode(lat: lat, lng: lng);
    if (!mounted) return;
    setState(() {
      _selectedSpot = (
        lat: lat,
        lng: lng,
        address: addr ?? '${lat.toStringAsFixed(5)}° N, ${lng.toStringAsFixed(5)}° E',
      );
    });
  }

  void _clearSelectedSpot() {
    _controller?.removeMarker(kDroppedPinMarkerId);
    if (mounted) setState(() => _selectedSpot = null);
  }

  void _clearNearbyService() {
    setState(() {
      _selectedServiceIdx = null;
      _nearbyPlaces = [];
    });
    _syncMarkersToOlaMap();
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
        lat: _currentCenterLat,
        lng: _currentCenterLng,
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

    await _inspectPlaceById(
      p.placeId,
      fallbackName: p.mainText ?? p.description,
      fallbackLat: p.lat,
      fallbackLng: p.lng,
    );
  }

  // ── Nearby Services Discovery ─────────────────────────────────────────────

  Future<void> _onNearbyServiceTapped(int idx) async {
    if (_selectedServiceIdx == idx) {
      // Deselect
      setState(() {
        _selectedServiceIdx = null;
        _nearbyPlaces = [];
      });
      _syncMarkersToOlaMap();
      return;
    }

    setState(() {
      _selectedServiceIdx = idx;
      _loadingNearby = true;
    });

    final service = _nearbyServices[idx];
    final places = await _ola.nearbySearch(
      lat: _currentCenterLat,
      lng: _currentCenterLng,
      types: service.type,
      radius: 5000,
    );

    if (!mounted) return;
    setState(() {
      _nearbyPlaces = places;
      _loadingNearby = false;
    });

    await _syncMarkersToOlaMap();
  }

  Future<void> _inspectPlaceById(
    String placeId, {
    String? fallbackName,
    double? fallbackLat,
    double? fallbackLng,
  }) async {
    // Show loading feedback or fetch cached
    OlaPlaceDetails? details = _cachedPoiDetails[placeId];
    if (details == null) {
      details = await _ola.getPlaceDetails(placeId, advanced: true);
      if (details != null) {
        _cachedPoiDetails[placeId] = details;
      }
    }

    // Fallback if details API returned null
    if (details == null && fallbackLat != null && fallbackLng != null) {
      details = OlaPlaceDetails(
        placeId: placeId,
        name: fallbackName ?? 'Civic Landmark',
        formattedAddress: '${fallbackLat.toStringAsFixed(4)}, ${fallbackLng.toStringAsFixed(4)}',
        lat: fallbackLat,
        lng: fallbackLng,
      );
    }

    if (details != null && mounted) {
      _currentCenterLat = details.lat;
      _currentCenterLng = details.lng;
      await _controller?.animateCamera(lat: details.lat, lng: details.lng, zoom: 16.5);
      _showPlaceDetailsSheet(details);
    }
  }

  Future<void> _goToMyLocation({bool initial = false}) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final perm = await _loc.ensurePermission();
      if (!_loc.isGranted(perm)) {
        if (!initial && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission needed to locate')),
          );
        }
        return;
      }
      final pos = await _loc.current();
      if (pos != null) {
        _userLat = pos.latitude;
        _userLng = pos.longitude;
        _currentCenterLat = pos.latitude;
        _currentCenterLng = pos.longitude;
        await _controller?.animateCamera(
          lat: pos.latitude,
          lng: pos.longitude,
          zoom: 16.0,
        );
        _controller?.showCurrentLocation();
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ── Sheets ────────────────────────────────────────────────────────────────

  void _showPlaceDetailsSheet(OlaPlaceDetails details) => showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _OlaPlaceDetailsSheet(
      details: details,
      userLat: _userLat ?? _currentCenterLat,
      userLng: _userLng ?? _currentCenterLng,
    ),
  );

  void _showReportSheet(Report r) => showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ModernReportSheet(report: r),
  );

  void _showLfSheet(LFItem l) => showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _ModernLfSheet(item: l),
  );

  void _showLayersSheet() => showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _LayersControlSheet(
      showReports: _showReportsLayer,
      showLf: _showLfLayer,
      showPoi: _showNearbyPoiLayer,
      onToggleReports: (v) {
        setState(() => _showReportsLayer = v);
        _syncMarkersToOlaMap();
      },
      onToggleLf: (v) {
        setState(() => _showLfLayer = v);
        _syncMarkersToOlaMap();
      },
      onTogglePoi: (v) {
        setState(() => _showNearbyPoiLayer = v);
        _syncMarkersToOlaMap();
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeService = _selectedServiceIdx != null
        ? _nearbyServices[_selectedServiceIdx!]
        : null;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090D12) : const Color(0xFFF6F8FB),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. Official Native Map View (Theme-aware Dark & Light tiles)
          OlaNativeMapWidget(
            initialLat: _currentCenterLat,
            initialLng: _currentCenterLng,
            initialZoom: 15.0,
            onMapReady: _onMapReady,
            onMarkerClicked: _onMarkerClicked,
            onMapClicked: _onMapClicked,
            onCameraIdle: (lat, lng) {
              if (lat != null && lng != null) {
                _currentCenterLat = lat;
                _currentCenterLng = lng;
              }
            },
          ),

          // 2. Glassmorphic Top Controls & Service Discovery
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Floating search bar with layer controls
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF131A22).withValues(alpha: 0.92)
                              : Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : const Color(0xFFE2E8F0),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(left: 14, right: 8),
                              child: Icon(
                                Icons.search,
                                color: Color(0xFF00E676),
                                size: 22,
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _searchCtrl,
                                onChanged: _onSearchChanged,
                                style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF111827),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: InputDecoration(
                                  fillColor: Colors.transparent,
                                  filled: false,
                                  hintText: 'Search city landmarks or places…',
                                  hintStyle: TextStyle(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.45)
                                        : const Color(0xFF9CA3AF),
                                    fontSize: 13,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            if (_searching)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
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
                                icon: Icon(
                                  Icons.close,
                                  size: 18,
                                  color: isDark ? Colors.white70 : const Color(0xFF6B7280),
                                ),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _onSearchChanged('');
                                },
                              ),
                            // Layers Filter Button
                            IconButton(
                              tooltip: 'Map Layers',
                              icon: const Icon(
                                Icons.layers_outlined,
                                size: 21,
                                color: Color(0xFF00E676),
                              ),
                              onPressed: _showLayersSheet,
                            ),
                            IconButton(
                              tooltip: 'Debug log',
                              icon: Icon(
                                _showLog ? Icons.close : Icons.bug_report,
                                size: 19,
                                color: _showLog
                                    ? NivaraColors.danger
                                    : (isDark ? Colors.white38 : Colors.black26),
                              ),
                              onPressed: () => setState(() => _showLog = !_showLog),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Autocomplete dropdown
                  if (_showSuggestions && _predictions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 250),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF131A22).withValues(alpha: 0.96)
                            : Colors.white.withValues(alpha: 0.98),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : const Color(0xFFE2E8F0),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
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
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : const Color(0xFFE5E7EB),
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
                                style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF111827),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: p.secondaryText != null
                                  ? Text(
                                      p.secondaryText!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white.withValues(alpha: 0.5)
                                            : const Color(0xFF6B7280),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : null,
                              trailing: Icon(
                                Icons.arrow_forward_ios,
                                size: 12,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                              onTap: () => _selectPrediction(p),
                            );
                          },
                        ),
                      ),
                    ),

                  const SizedBox(height: 10),

                  // Nearby Emergency & Civic Services Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF131A22).withValues(alpha: 0.90)
                              : Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : const Color(0xFFE2E8F0),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.near_me, size: 11, color: Color(0xFF00E676)),
                            const SizedBox(width: 4),
                            Text(
                              'NEARBY SERVICES',
                              style: TextStyle(
                                color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (activeService != null) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _clearNearbyService,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: activeService.color.withValues(alpha: isDark ? 0.18 : 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: activeService.color.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${activeService.icon} ${activeService.label}',
                                  style: TextStyle(
                                    color: activeService.color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.close,
                                  size: 13,
                                  color: activeService.color,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),

                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _nearbyServices.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final s = _nearbyServices[i];
                        final selected = _selectedServiceIdx == i;
                        return GestureDetector(
                          onTap: () => _onNearbyServiceTapped(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? s.color.withValues(alpha: 0.22)
                                  : (isDark
                                      ? const Color(0xFF131A22).withValues(alpha: 0.88)
                                      : Colors.white.withValues(alpha: 0.95)),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? s.color
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.12)
                                        : const Color(0xFFE2E8F0)),
                                width: selected ? 1.5 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: selected
                                      ? s.color.withValues(alpha: 0.3)
                                      : Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                  blurRadius: selected ? 8 : 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(s.icon, style: const TextStyle(fontSize: 13)),
                                const SizedBox(width: 6),
                                Text(
                                  s.label,
                                  style: TextStyle(
                                    color: selected
                                        ? s.color
                                        : (isDark ? Colors.white : const Color(0xFF111827)),
                                    fontSize: 12,
                                    fontWeight:
                                        selected ? FontWeight.w800 : FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Nearby POI suggestions horizontal list
                  if (_loadingNearby) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF131A22).withValues(alpha: 0.85)
                            : Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF00E676),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Searching ${activeService?.label ?? 'places'}…',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_nearbyPlaces.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _nearbyPlaces.take(10).length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final p = _nearbyPlaces[i];
                          final color = activeService?.color ?? const Color(0xFF00E676);
                          return GestureDetector(
                            onTap: () => _inspectPlaceById(
                              p.placeId,
                              fallbackName: p.mainText ?? p.description,
                              fallbackLat: p.lat,
                              fallbackLng: p.lng,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF131A22).withValues(alpha: 0.92)
                                    : Colors.white.withValues(alpha: 0.96),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: color.withValues(alpha: isDark ? 0.4 : 0.55),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_city, size: 13, color: color),
                                  const SizedBox(width: 6),
                                  Text(
                                    p.mainText ?? p.description,
                                    style: TextStyle(
                                      color: isDark ? Colors.white : const Color(0xFF111827),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 3. Quick Spot Tap Inspector Floating Card
          if (_selectedSpot != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 90,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF131A22).withValues(alpha: 0.96)
                          : Colors.white.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E676).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.place, color: Color(0xFF00E676), size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedSpot!.address,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isDark ? Colors.white : const Color(0xFF111827),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${_selectedSpot!.lat.toStringAsFixed(5)}° N, ${_selectedSpot!.lng.toStringAsFixed(5)}° E',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.5)
                                          : const Color(0xFF6B7280),
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.close,
                                color: isDark ? Colors.white60 : Colors.black54,
                                size: 20,
                              ),
                              onPressed: _clearSelectedSpot,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () {
                                final spot = _selectedSpot!;
                                _clearSelectedSpot();
                                context.push(
                                  Routes.report,
                                  extra: (
                                    lat: spot.lat,
                                    lng: spot.lng,
                                    address: spot.address,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.add_location_alt, color: Colors.black, size: 20),
                              label: const Text(
                                'Report Issue At This Location',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
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

          // 4. GPS Recenter FAB
          Positioned(
            bottom: 24,
            right: 18,
            child: FloatingActionButton.small(
              heroTag: 'civic_recenter_2026',
              backgroundColor: isDark
                  ? const Color(0xFF151D28).withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.95),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              onPressed: _locating ? null : () => _goToMyLocation(),
              child: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF00E676),
                      ),
                    )
                  : const Icon(Icons.my_location, color: Color(0xFF00E676)),
            ),
          ),

          if (_showLog) const _LogOverlay(),
        ],
      ),
    );
  }
}

/// 2026-Level Futuristic Place Details & Navigation Sheet powered by Ola Places API.
class _OlaPlaceDetailsSheet extends StatelessWidget {
  const _OlaPlaceDetailsSheet({
    required this.details,
    required this.userLat,
    required this.userLng,
  });

  final OlaPlaceDetails details;
  final double userLat;
  final double userLng;

  String _formatDistance() {
    final meters = Geolocator.distanceBetween(
      userLat,
      userLng,
      details.lat,
      details.lng,
    );
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m away';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km away';
  }

  ({String icon, Color color, String label}) _resolveCategoryMeta() {
    final types = details.types.map((t) => t.toLowerCase()).toList();
    if (types.any((t) => t.contains('hospital') || t.contains('health') || t.contains('doctor'))) {
      return (icon: '🏥', color: const Color(0xFFFF5252), label: 'HOSPITAL & EMERGENCY');
    }
    if (types.any((t) => t.contains('police'))) {
      return (icon: '👮', color: const Color(0xFF448AFF), label: 'POLICE STATION');
    }
    if (types.any((t) => t.contains('fire'))) {
      return (icon: '🚒', color: const Color(0xFFFF6E40), label: 'FIRE STATION');
    }
    if (types.any((t) => t.contains('transit') || t.contains('subway') || t.contains('bus') || t.contains('train'))) {
      return (icon: '🚌', color: const Color(0xFF00E676), label: 'TRANSIT STATION');
    }
    if (types.any((t) => t.contains('pharmacy') || t.contains('drugstore'))) {
      return (icon: '💊', color: const Color(0xFFE040FB), label: 'PHARMACY');
    }
    if (types.any((t) => t.contains('government') || t.contains('civic') || t.contains('city_hall'))) {
      return (icon: '🏛️', color: const Color(0xFFFFD700), label: 'CIVIC OFFICE');
    }
    return (icon: '📍', color: const Color(0xFF00E676), label: 'CIVIC LANDMARK');
  }

  Future<void> _openGoogleMapsNavigation(BuildContext context) async {
    final destLat = details.lat;
    final destLng = details.lng;
    final destName = Uri.encodeComponent(details.name);

    // 1. Universal Google Maps Navigation URL
    final gmapsNavUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng',
    );

    try {
      if (await canLaunchUrl(gmapsNavUrl)) {
        await launchUrl(gmapsNavUrl, mode: LaunchMode.externalApplication);
      } else {
        // 2. Native geo intent fallback
        final geoUri = Uri.parse('geo:$destLat,$destLng?q=$destLat,$destLng($destName)');
        if (await canLaunchUrl(geoUri)) {
          await launchUrl(geoUri, mode: LaunchMode.externalApplication);
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open external maps')),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Navigation error: $e')),
        );
      }
    }
  }

  Future<void> _makeCall(BuildContext context) async {
    final phone = details.phoneNumber;
    if (phone != null && phone.isNotEmpty) {
      final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
      final uri = Uri.parse('tel:$clean');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    }

    // Default Emergency Helpline based on category
    final types = details.types.map((t) => t.toLowerCase()).toList();
    String emergencyNum = '112';
    if (types.any((t) => t.contains('hospital'))) emergencyNum = '108';
    if (types.any((t) => t.contains('police'))) emergencyNum = '100';
    if (types.any((t) => t.contains('fire'))) emergencyNum = '101';

    final uri = Uri.parse('tel:$emergencyNum');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final meta = _resolveCategoryMeta();
    final photoUrl = OlaMapsService.instance.getPhotoUrl(details.photoReference);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF10161E).withValues(alpha: 0.97)
                : Colors.white.withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: meta.color.withValues(alpha: isDark ? 0.3 : 0.5),
                width: 1.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Top Badge & Distance
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                      decoration: BoxDecoration(
                        color: meta.color.withValues(alpha: isDark ? 0.18 : 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: meta.color.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(meta.icon, style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 5),
                          Text(
                            meta.label,
                            style: TextStyle(
                              color: meta.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.navigation, size: 12, color: Color(0xFF00E676)),
                          const SizedBox(width: 4),
                          Text(
                            _formatDistance(),
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF111827),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Place Name
                Text(
                  details.name,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF111827),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),

                const SizedBox(height: 4),

                // Formatted Address
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.place_outlined,
                        color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        details.formattedAddress,
                        style: TextStyle(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.75)
                              : const Color(0xFF4B5563),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),

                // Rating (if available from place details)
                if (details.rating != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB300).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, size: 13, color: Color(0xFFFFB300)),
                        const SizedBox(width: 4),
                        Text(
                          '${details.rating!.toStringAsFixed(1)}${details.userRatingsTotal != null ? " (${details.userRatingsTotal})" : ""}',
                          style: const TextStyle(
                            color: Color(0xFFFFB300),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Optional Photo Banner
                if (photoUrl != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      photoUrl,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Primary & Secondary Action Buttons
                Row(
                  children: [
                    // Navigate Button
                    Expanded(
                      flex: 6,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00E676).withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => _openGoogleMapsNavigation(context),
                          icon: const Icon(Icons.directions, color: Colors.black, size: 20),
                          label: const Text(
                            'Navigate in Maps',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Call Button
                    Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1B2430) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.call, color: Color(0xFF00E676), size: 20),
                        tooltip: 'Call Facility',
                        onPressed: () => _makeCall(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Share Location
                    Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1B2430) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.share,
                          color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                          size: 20,
                        ),
                        tooltip: 'Share Location',
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(
                              text: '${details.name}\n${details.formattedAddress}\nhttps://maps.google.com/?q=${details.lat},${details.lng}',
                            ),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Location copied to clipboard')),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Report Civic Issue Here Button
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : const Color(0xFFCBD5E1),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      context.push(
                        Routes.report,
                        extra: (
                          lat: details.lat,
                          lng: details.lng,
                          address: details.formattedAddress.isNotEmpty
                              ? details.formattedAddress
                              : details.name,
                        ),
                      );
                    },
                    icon: const Icon(Icons.report_problem_outlined, color: Color(0xFFFFB300), size: 18),
                    label: Text(
                      'Report a Civic Issue Near This Facility',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF111827),
                        fontSize: 13,
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
    );
  }
}

/// Floating Layer Control Sheet to toggle visibility of different data layers.
class _LayersControlSheet extends StatelessWidget {
  const _LayersControlSheet({
    required this.showReports,
    required this.showLf,
    required this.showPoi,
    required this.onToggleReports,
    required this.onToggleLf,
    required this.onTogglePoi,
  });

  final bool showReports;
  final bool showLf;
  final bool showPoi;
  final ValueChanged<bool> onToggleReports;
  final ValueChanged<bool> onToggleLf;
  final ValueChanged<bool> onTogglePoi;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF10161E).withValues(alpha: 0.96)
                : Colors.white.withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Civic Map Layers',
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF111827),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Customize which data feeds are displayed on the civic map',
                  style: TextStyle(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.6)
                        : const Color(0xFF6B7280),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB300).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.report_problem, color: Color(0xFFFFB300), size: 20),
                  ),
                  title: Text(
                    'Open Citizen Reports',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF111827),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Broken roads, streetlights, garbage & water issues',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                  value: showReports,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: onToggleReports,
                ),
                Divider(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE5E7EB),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF29B6F6).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.inventory_2, color: Color(0xFF29B6F6), size: 20),
                  ),
                  title: Text(
                    'Lost & Found Items',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF111827),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Active lost valuables & found items across the city',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                  value: showLf,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: onToggleLf,
                ),
                Divider(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE5E7EB),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.local_hospital, color: Color(0xFF00E676), size: 20),
                  ),
                  title: Text(
                    'Emergency & Civic Facilities',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF111827),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Hospitals, police stations, transit hubs & govt offices',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                  value: showPoi,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: onTogglePoi,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 2026-Level Futuristic Report Inspection Sheet.
class _ModernReportSheet extends StatelessWidget {
  const _ModernReportSheet({required this.report});
  final Report report;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cat = report.category;
    final status = report.status;
    final color = switch (status) {
      ReportStatus.submitted => const Color(0xFFFFB300),
      ReportStatus.inProgress => const Color(0xFF29B6F6),
      ReportStatus.resolved => const Color(0xFF00E676),
      _ => const Color(0xFF90A4AE),
    };

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF10161E).withValues(alpha: 0.95)
                : Colors.white.withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(categoryIcon(cat), color: color, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            report.title ?? cat.label,
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF111827),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            report.address ?? '${report.lat.toStringAsFixed(4)}, ${report.lng.toStringAsFixed(4)}',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : const Color(0xFF6B7280),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withValues(alpha: 0.6)),
                      ),
                      child: Text(
                        status.label,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (report.description != null && report.description!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    report.description!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.8)
                          : const Color(0xFF374151),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        context.push(Routes.reportDetail, extra: report);
                      },
                      icon: const Icon(Icons.arrow_forward, color: Colors.black),
                      label: const Text(
                        'View Full Details & Proof',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 14,
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
    );
  }
}

/// 2026-Level Futuristic Lost & Found Sheet.
class _ModernLfSheet extends StatelessWidget {
  const _ModernLfSheet({required this.item});
  final LFItem item;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = item.isLost ? const Color(0xFFFF5252) : const Color(0xFF00E676);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF10161E).withValues(alpha: 0.95)
                : Colors.white.withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        item.isLost ? Icons.search : Icons.inventory_2,
                        color: color,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF111827),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.locationLabel ?? '${item.lat.toStringAsFixed(4)}, ${item.lng.toStringAsFixed(4)}',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : const Color(0xFF6B7280),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      context.push(Routes.lostFoundDetail, extra: item);
                    },
                    child: Text(
                      'View ${item.isLost ? 'Lost' : 'Found'} Item Details',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// On-screen mirror of the file log.
class _LogOverlay extends StatelessWidget {
  const _LogOverlay();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 64;
    return Positioned(
      top: top,
      left: 12,
      right: 12,
      bottom: 160,
      child: Material(
        color: Colors.black.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Debug log',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'file: ${DebugLogger.instance.resolvedPath}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
              const Divider(color: Colors.white24, height: 12),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: DebugLogger.instance.revision,
                  builder: (context, _, child) {
                    final allLines = DebugLogger.instance.recent;
                    final lines = allLines.length > 60
                        ? allLines.sublist(allLines.length - 60)
                        : allLines;
                    if (lines.isEmpty) {
                      return const Center(
                        child: Text(
                          'Log is empty.',
                          style: TextStyle(color: Colors.white38),
                        ),
                      );
                    }
                    return ListView.builder(
                      reverse: true,
                      itemCount: lines.length,
                      itemBuilder: (context, i) {
                        final line = lines[lines.length - 1 - i];
                        final isErr = line.contains(' [E] ');
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1.5),
                          child: Text(
                            line,
                            style: TextStyle(
                              color: isErr
                                  ? const Color(0xFFFF6B6B)
                                  : Colors.white70,
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
