import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
/// • Full native Android Ola Map rendering with Ola vector tiles & data
/// • Glassmorphic top floating Search Bar with Ola Places Autocomplete
/// • Nearby POI Discovery Pills (Hospitals, Police, Transit, Civic Offices)
/// • Supabase Realtime synchronization with live colored marker pins
/// • Tap-to-inspect reports, Lost & Found items, and custom spot reporting
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
  final _reports = <String, Report>{};
  final _lfItems = <String, LFItem>{};
  StreamSubscription? _reportsSub;
  StreamSubscription? _lfSub;
  bool _mapReady = false;
  bool _locating = false;
  bool _showLog = false;

  double _currentCenterLat = kDefaultLat;
  double _currentCenterLng = kDefaultLng;

  // Search & Autocomplete
  final _searchCtrl = TextEditingController();
  Timer? _debounceTimer;
  List<OlaPlacePrediction> _predictions = [];
  bool _searching = false;
  bool _showSuggestions = false;

  // Nearby discovery filters
  final List<({String label, String icon, String? type})> _nearbyFilters = [
    (label: 'All Issues', icon: '📍', type: null),
    (label: 'Hospitals', icon: '🏥', type: 'hospital'),
    (label: 'Police', icon: '👮', type: 'police'),
    (label: 'Transit', icon: '🚌', type: 'transit_station'),
    (label: 'Govt Offices', icon: '🏛️', type: 'local_government_office'),
  ];
  int _selectedFilterIdx = 0;
  List<OlaPlacePrediction> _nearbyPlaces = [];
  bool _loadingNearby = false;

  // Quick spot tap inspect
  ({double lat, double lng, String address})? _selectedSpot;

  @override
  void initState() {
    super.initState();
    _log.log('MAP', 'CivicMapScreen initState (Native Ola Map)');
    _seedFromRest();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    _reportsSub?.cancel();
    _lfSub?.cancel();
    super.dispose();
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
              _lfItems[r['id'] as String] = LFItem.fromMap(r);
            } catch (_) {}
          }
          if (_mapReady) _syncMarkersToOlaMap();
        });
  }

  Future<void> _syncMarkersToOlaMap() async {
    final c = _controller;
    if (c == null) return;

    await c.clearMarkers();

    // Add only active/open reports (resolved are filtered out)
    for (final r in _reports.values) {
      if (r.status == ReportStatus.resolved ||
          r.status == ReportStatus.closed ||
          r.status == ReportStatus.duplicate) {
        continue;
      }
      final color = switch (r.status) {
        ReportStatus.submitted => const Color(0xFFFFB300),
        ReportStatus.inProgress => const Color(0xFF29B6F6),
        _ => const Color(0xFF90A4AE),
      };
      await c.addMarker(
        id: 'report_${r.id}',
        lat: r.lat,
        lng: r.lng,
        color: color,
      );
    }

    // Add L&F items
    for (final l in _lfItems.values) {
      final color = l.isLost ? const Color(0xFFFF5252) : const Color(0xFF00E676);
      await c.addMarker(
        id: 'lf_${l.id}',
        lat: l.lat,
        lng: l.lng,
        snippet: '${l.isLost ? 'Lost' : 'Found'}: ${l.title}',
        color: color,
      );
    }
  }

  // ── Native Map Callbacks ──────────────────────────────────────────────────

  void _onMapReady(OlaNativeMapController controller) {
    _controller = controller;
    _mapReady = true;
    _syncMarkersToOlaMap();
    _goToMyLocation(initial: true);
  }

  void _onMarkerClicked(String markerId) {
    if (markerId.startsWith('report_')) {
      final id = markerId.substring('report_'.length);
      final r = _reports[id];
      if (r != null) _showReportSheet(r);
    } else if (markerId.startsWith('lf_')) {
      final id = markerId.substring('lf_'.length);
      final l = _lfItems[id];
      if (l != null) _showLfSheet(l);
    }
  }

  Future<void> _onMapClicked(double lat, double lng) async {
    final addr = await _ola.reverseGeocode(lat: lat, lng: lng);
    if (!mounted) return;
    setState(() {
      _selectedSpot = (
        lat: lat,
        lng: lng,
        address: addr ?? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
      );
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

    double? lat = p.lat;
    double? lng = p.lng;

    if (lat == null || lng == null) {
      final details = await _ola.getPlaceDetails(p.placeId);
      if (details != null) {
        lat = details.lat;
        lng = details.lng;
      }
    }

    if (lat != null && lng != null) {
      _currentCenterLat = lat;
      _currentCenterLng = lng;
      await _controller?.animateCamera(lat: lat, lng: lng, zoom: 16.5);
    }
  }

  Future<void> _onNearbyFilterSelected(int idx) async {
    setState(() => _selectedFilterIdx = idx);
    final filter = _nearbyFilters[idx];
    if (filter.type == null) {
      setState(() => _nearbyPlaces = []);
      return;
    }

    setState(() => _loadingNearby = true);
    final places = await _ola.nearbySearch(
      lat: _currentCenterLat,
      lng: _currentCenterLng,
      types: filter.type,
      radius: 3000,
    );
    if (!mounted) return;
    setState(() {
      _nearbyPlaces = places;
      _loadingNearby = false;
    });
  }

  Future<void> _selectNearbyPlace(OlaPlacePrediction p) async {
    if (p.lat != null && p.lng != null) {
      _currentCenterLat = p.lat!;
      _currentCenterLng = p.lng!;
      await _controller?.animateCamera(lat: p.lat!, lng: p.lng!, zoom: 16.5);
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
            const SnackBar(content: Text('Location permission needed')),
          );
        }
        return;
      }
      final pos = await _loc.current();
      if (pos != null) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D12),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. Official Native Ola Map View
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

          // 2. Futuristic Glassmorphic Top Bar & Autocomplete
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Floating search card
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
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
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search city landmarks or places with Ola…',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 13,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            if (_searching)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
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
                                icon: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.white70,
                                ),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _onSearchChanged('');
                                },
                              ),
                            IconButton(
                              tooltip: 'Debug log',
                              icon: Icon(
                                _showLog ? Icons.close : Icons.bug_report,
                                size: 20,
                                color: _showLog
                                    ? NivaraColors.danger
                                    : Colors.white38,
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
                        color: const Color(0xFF131A22).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 20,
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

                  const SizedBox(height: 8),

                  // Nearby category filter pills
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
                          onTap: () => _onNearbyFilterSelected(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF00E676).withValues(alpha: 0.2)
                                  : const Color(0xFF131A22).withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF00E676).withValues(alpha: 0.8)
                                    : Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Text(
                              '${f.icon} ${f.label}',
                              style: TextStyle(
                                color: selected
                                    ? const Color(0xFF00E676)
                                    : Colors.white70,
                                fontSize: 12,
                                fontWeight:
                                    selected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Nearby POI suggestions horizontal list
                  if (_loadingNearby) ...[
                    const SizedBox(height: 8),
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
                            'Searching landmarks via Ola…',
                            style: TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_nearbyPlaces.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 32,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _nearbyPlaces.take(8).length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (context, i) {
                          final p = _nearbyPlaces[i];
                          return ActionChip(
                            backgroundColor: const Color(0xFF16202B),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                            label: Text(
                              p.mainText ?? p.description,
                              style: const TextStyle(color: Colors.white, fontSize: 11),
                            ),
                            avatar: const Icon(
                              Icons.near_me,
                              size: 13,
                              color: Color(0xFF00E676),
                            ),
                            onPressed: () => _selectNearbyPlace(p),
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
                      color: const Color(0xFF131A22).withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
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
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${_selectedSpot!.lat.toStringAsFixed(5)}° N, ${_selectedSpot!.lng.toStringAsFixed(5)}° E',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                              onPressed: () => setState(() => _selectedSpot = null),
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
                                setState(() => _selectedSpot = null);
                                context.push(
                                  Routes.report,
                                  extra: spot,
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
              backgroundColor: const Color(0xFF151D28).withValues(alpha: 0.9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
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

/// 2026-Level Futuristic Report Inspection Sheet.
class _ModernReportSheet extends StatelessWidget {
  const _ModernReportSheet({required this.report});
  final Report report;

  @override
  Widget build(BuildContext context) {
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
            color: const Color(0xFF10161E).withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
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
                      color: Colors.white.withValues(alpha: 0.3),
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            report.address ?? '${report.lat.toStringAsFixed(4)}, ${report.lng.toStringAsFixed(4)}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
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
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
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
    final color = item.isLost ? const Color(0xFFFF5252) : const Color(0xFF00E676);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
          decoration: BoxDecoration(
            color: const Color(0xFF10161E).withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
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
                      color: Colors.white.withValues(alpha: 0.3),
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.locationLabel ?? '${item.lat.toStringAsFixed(4)}, ${item.lng.toStringAsFixed(4)}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
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
