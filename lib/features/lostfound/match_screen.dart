import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/enums.dart';
import '../../models/lf_item.dart';
import 'item_card.dart';

/// Shows candidate matches for a given [item]: items of the *opposite* type
/// (lost → found, found → lost), same category, within [kLfMatchRadiusMeters]
/// and [kLfMatchWindowDays], ranked nearest-first.
///
/// Backed by the `find_nearby_items` Postgres RPC (PostGIS `ST_DWithin`), so the
/// proximity + time filtering happens server-side. This is the "basic match
/// display" for build-order #5 — a full two-sided confirmation flow (writing
/// `lf_matches`) can layer on later.
class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key, required this.item});

  final LFItem item;

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  late Future<List<_Match>> _future;

  LFItemType get _lookingFor =>
      widget.item.isLost ? LFItemType.found : LFItemType.lost;

  @override
  void initState() {
    super.initState();
    _future = _findMatches();
  }

  Future<List<_Match>> _findMatches() async {
    final rows = await supabase.rpc(
      'find_nearby_items',
      params: {
        'p_lat': widget.item.lat,
        'p_lng': widget.item.lng,
        'p_radius_km': kLfMatchRadiusMeters / 1000.0,
        'p_category': widget.item.category.wire,
        'p_item_type': _lookingFor.wire,
        'p_within_days': kLfMatchWindowDays,
      },
    );

    final list = (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final item = LFItem(
        id: m['id'] as String,
        userId: '',
        itemType: _lookingFor,
        category: LFCategory.fromWire(m['category'] as String?),
        title: (m['title'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
        lat: toDouble(m['lat']),
        lng: toDouble(m['lng']),
        eventDate: toDateTimeOrNull(m['event_date']) ?? DateTime.now(),
      );
      return _Match(
        item: item,
        distanceMeters: toDouble(m['distance_km']) * 1000,
      );
    }).toList();
    return list;
  }

  Future<void> _refresh() async {
    final next = _findMatches();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final lookingLost = _lookingFor == LFItemType.lost;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          lookingLost ? 'Matching lost reports' : 'Matching found items',
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<_Match>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _Message(
                icon: Icons.cloud_off,
                title: 'Could not search',
                subtitle: '${snap.error}',
                scrollable: true,
              );
            }
            final matches = snap.data ?? const [];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Header(item: widget.item, count: matches.length),
                const SizedBox(height: 16),
                if (matches.isEmpty)
                  const _Message(
                    icon: Icons.search,
                    title: 'No matches yet',
                    subtitle:
                        'Nothing nearby of the same kind for now. We keep '
                        'looking — check back, or pull to refresh.',
                  )
                else
                  ...matches.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: LFItemCard(
                        item: m.item,
                        distanceMeters: m.distanceMeters,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Match {
  const _Match({required this.item, required this.distanceMeters});
  final LFItem item;
  final double distanceMeters;
}

class _Header extends StatelessWidget {
  const _Header({required this.item, required this.count});
  final LFItem item;
  final int count;

  @override
  Widget build(BuildContext context) {
    final accent = item.isLost ? NivaraColors.danger : NivaraColors.success;
    final radiusKm = (kLfMatchRadiusMeters / 1000).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(lfCategoryIcon(item.category), color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            count == 0
                ? 'Searching ${item.category.label} within $radiusKm km, '
                      'reported in the last $kLfMatchWindowDays days.'
                : '$count nearby ${count == 1 ? 'candidate' : 'candidates'} '
                      'within $radiusKm km · same category · last '
                      '$kLfMatchWindowDays days.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.scrollable = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: scheme.outline),
        const SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
    if (!scrollable) {
      return Padding(padding: const EdgeInsets.all(24), child: content);
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [const SizedBox(height: 80), content],
    );
  }
}
