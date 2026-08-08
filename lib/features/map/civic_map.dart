import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../models/enums.dart';
import '../../models/lf_item.dart';
import '../../models/report.dart';
import '../../features/report/category_grid.dart';

/// Live civic map — MapLibre (Ola vector style + OSM raster fallback) with
/// realtime Symbol pins for Reports (from `reports` table) and Lost & Found
/// items (from `lf_items`). Colours by status/category follow the brand palette.
class CivicMapScreen extends ConsumerStatefulWidget {
  const CivicMapScreen({super.key});

  @override
  ConsumerState<CivicMapScreen> createState() => _CivicMapScreenState();
}

class _CivicMapScreenState extends ConsumerState<CivicMapScreen> {
  MapLibreMapController? _controller;
  final _reports = <String, Report>{};
  final _lfItems = <String, LFItem>{};
  final _symbolIds = <String, String>{}; // map itemId -> symbolId
  StreamSubscription? _reportsSub;
  StreamSubscription? _lfSub;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _controller?.onSymbolTapped.remove(_onSymbolTapped);
    _reportsSub?.cancel();
    _lfSub?.cancel();
    super.dispose();
  }

  void _subscribeRealtime() {
    _reportsSub = supabase
        .from(kTableReports)
        .stream(primaryKey: ['id'])
        .listen((rows) {
          for (final r in rows) {
            _reports[r['id'] as String] = Report.fromMap(r);
          }
          if (_mapReady) _rebuildSymbols();
        });

    _lfSub = supabase
        .from(kTableLfItems)
        .stream(primaryKey: ['id'])
        .listen((rows) {
          for (final r in rows) {
            _lfItems[r['id'] as String] = LFItem.fromMap(r);
          }
          if (_mapReady) _rebuildSymbols();
        });
  }

  Future<void> _rebuildSymbols() async {
    if (_controller == null || _controller!.symbolManager == null) return;

    // Clear existing symbols
    await _controller!.clearSymbols();

    // Add report symbols
    for (final r in _reports.values) {
      final options = _reportSymbolOptions(r);
      final sym = await _controller!.addSymbol(options);
      _symbolIds[r.id] = sym.id;
    }

    // Add Lost/Found symbols
    for (final l in _lfItems.values) {
      final options = _lfSymbolOptions(l);
      final sym = await _controller!.addSymbol(options);
      _symbolIds['lf_${l.id}'] = sym.id;
    }
  }

  SymbolOptions _reportSymbolOptions(Report r) {
    return SymbolOptions(
      geometry: LatLng(r.lat, r.lng),
      iconImage: 'marker', // default built-in marker
      iconSize: 1.0,
      iconAnchor: 'bottom',
      iconOffset: const Offset(0, -5),
      iconColor: _reportPinColor(r),
      draggable: false,
      zIndex: 10,
    );
  }

  SymbolOptions _lfSymbolOptions(LFItem l) {
    final isLost = l.itemType == LFItemType.lost;
    return SymbolOptions(
      geometry: LatLng(l.lat, l.lng),
      iconImage: 'marker',
      iconSize: 1.0,
      iconAnchor: 'bottom',
      iconOffset: const Offset(0, -5),
      iconColor: isLost ? '#E74C3C' : '#27AE60', // danger red / success green
      draggable: false,
      zIndex: 10,
    );
  }

  String _reportPinColor(Report r) {
    switch (r.status) {
      case ReportStatus.resolved:
        return '#27AE60'; // success green
      case ReportStatus.inProgress:
      case ReportStatus.acknowledged:
        return '#1B6CA8'; // primary blue
      case ReportStatus.submitted:
        return '#F5A623'; // accent amber
      default:
        return '#95A5A6'; // grey
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    _controller?.onSymbolTapped.add(_onSymbolTapped);
    _mapReady = true;
    _rebuildSymbols();
    _moveToDefault();
  }

  void _moveToDefault() {
    _controller?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(kDefaultLat, kDefaultLng),
          zoom: kDefaultZoom,
        ),
      ),
    );
  }

  void _onSymbolTapped(Symbol symbol) {
    final itemId = _symbolIds.entries
        .firstWhere(
          (e) => e.value == symbol.id,
          orElse: () => const MapEntry('', ''),
        )
        .key;
    if (itemId.isEmpty) return;

    if (itemId.startsWith('lf_')) {
      final lfId = itemId.substring(3);
      final item = _lfItems[lfId];
      if (item != null) _showLfSheet(item);
    } else {
      final report = _reports[itemId];
      if (report != null) _showReportSheet(report);
    }
  }

  void _showReportSheet(Report r) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ReportBottomSheet(report: r),
    );
  }

  void _showLfSheet(LFItem l) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => _LfBottomSheet(item: l),
    );
  }

  @override
  Widget build(BuildContext context) {
    final styleUrl = '$kOlaVectorStyleUrl?api_key=$kOlaMapsApiKey';

    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(kDefaultLat, kDefaultLng),
              zoom: kDefaultZoom,
            ),
            styleString: styleUrl,
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: () {
              // Add OSM raster as a fallback layer
              _controller?.addSource(
                'osm',
                RasterSourceProperties(
                  url: kOsmRasterTileUrl,
                  tileSize: 256,
                  minzoom: 0,
                  maxzoom: 19,
                  attribution: '© OpenStreetMap contributors',
                ),
              );
              _controller?.addLayer(
                'osm-fallback',
                'osm',
                RasterLayerProperties(rasterOpacity: 0.5),
              );
            },
            myLocationEnabled: true,
            myLocationTrackingMode: MyLocationTrackingMode.tracking,
            compassEnabled: true,
            trackCameraPosition: true,
            annotationOrder: const [AnnotationType.symbol],
            annotationConsumeTapEvents: const [AnnotationType.symbol],
          ),
          Positioned(
            bottom: 100,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              onPressed: _moveToDefault,
              backgroundColor: NivaraColors.primary,
              child: const Icon(Icons.my_location, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportBottomSheet extends StatelessWidget {
  const _ReportBottomSheet({required this.report});
  final Report report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(categoryIcon(report.category), color: NivaraColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  report.category.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              _StatusChip(status: report.status),
            ],
          ),
          const SizedBox(height: 12),
          if (report.title != null) ...[
            Text(report.title!,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
          ],
          Text(report.description ?? '',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.location_on_outlined,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '${report.lat.toStringAsFixed(4)}, ${report.lng.toStringAsFixed(4)}',
                style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          if (report.address != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.place_outlined,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(report.address!,
                      style: Theme.of(context).textTheme.bodySmall)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _InfoPill(icon: Icons.flag_outlined, text: report.severity.label),
              const SizedBox(width: 8),
              _InfoPill(
                  icon: report.source == 'SENSORWATCH'
                      ? Icons.radar
                      : Icons.edit,
                  text: report.source),
              const SizedBox(width: 8),
              _InfoPill(
                  icon: Icons.verified_user_outlined,
                  text: report.isCommunityVerified ? 'Verified' : 'Unverified'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.directions),
              label: const Text('Navigate'),
              onPressed: () {
                Navigator.pop(context);
                // TODO: open in maps app
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LfBottomSheet extends StatelessWidget {
  const _LfBottomSheet({required this.item});
  final LFItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLost = item.itemType == LFItemType.lost;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLost ? Icons.search_off : Icons.inventory_2,
                color: isLost ? NivaraColors.danger : NivaraColors.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Chip(
                label: Text(isLost ? 'LOST' : 'FOUND'),
                backgroundColor:
                    (isLost ? NivaraColors.danger : NivaraColors.success)
                        .withValues(alpha: 0.15),
                labelStyle: TextStyle(
                    color: isLost ? NivaraColors.danger : NivaraColors.success,
                    fontWeight: FontWeight.w600,
                    fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(item.description,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.category_outlined,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(item.category.label,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 16),
              Icon(Icons.contact_phone_outlined,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(item.contactMethod,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          if (item.rewardAmount != null && item.rewardAmount! > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.card_giftcard,
                    size: 16, color: NivaraColors.accent),
                const SizedBox(width: 4),
                Text('Reward: ₹${item.rewardAmount}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: NivaraColors.accent,
                          fontWeight: FontWeight.w600,
                        )),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.message_outlined),
              label: const Text('Contact'),
              onPressed: () {
                Navigator.pop(context);
                // TODO: open contact flow
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final ReportStatus status;

  static const _colors = {
    ReportStatus.submitted: NivaraColors.accent,
    ReportStatus.acknowledged: NivaraColors.primary,
    ReportStatus.inProgress: NivaraColors.primary,
    ReportStatus.resolved: NivaraColors.success,
    ReportStatus.closed: Colors.grey,
    ReportStatus.duplicate: Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[status] ?? NivaraColors.primary;
    return Chip(
      label: Text(status.label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.15),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  )),
        ],
      ),
    );
  }
}