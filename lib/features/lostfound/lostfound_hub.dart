import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../models/enums.dart';
import '../../models/lf_item.dart';
import '../../router.dart';
import 'item_card.dart';

/// Lost & Found hub: two prominent entry points (report lost / report found)
/// over a live feed of recent active items. Tapping an item opens its match
/// list so the user can eyeball counterparts. The feed streams from `lf_items`
/// via Supabase Realtime — new posts appear without a manual refresh.
class LostFoundHub extends StatefulWidget {
  const LostFoundHub({super.key});

  @override
  State<LostFoundHub> createState() => _LostFoundHubState();
}

class _LostFoundHubState extends State<LostFoundHub> {
  final _items = <String, LFItem>{};
  StreamSubscription? _sub;
  bool _loaded = false;
  String? _error;
  LFItemType? _filter; // null = all

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// One-time fetch so the feed always populates (works regardless of whether
  /// Realtime is enabled), then subscribe for live updates on top. If the
  /// stream errors (e.g. Realtime not enabled for lf_items yet), we keep the
  /// fetched rows and simply forgo live refresh — the feature still works.
  Future<void> _load() async {
    try {
      final rows = await supabase
          .from(kTableLfItems)
          .select()
          .eq('status', 'ACTIVE')
          .order('created_at', ascending: false);
      for (final r in rows) {
        try {
          final item = LFItem.fromMap(r);
          _items[item.id] = item;
        } catch (_) {
          /* skip malformed row */
        }
      }
      if (mounted) setState(() => _loaded = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _error = '$e';
        });
      }
    }
    _subscribe();
  }

  void _subscribe() {
    _sub = supabase
        .from(kTableLfItems)
        .stream(primaryKey: ['id'])
        .order('created_at')
        .listen(
          (rows) {
            for (final r in rows) {
              try {
                final item = LFItem.fromMap(r);
                if (item.status == 'ACTIVE') {
                  _items[item.id] = item;
                } else {
                  _items.remove(item.id);
                }
              } catch (_) {
                /* skip malformed row */
              }
            }
            // A successful stream event means live data is flowing — clear any
            // earlier fetch error.
            if (mounted) setState(() => _error = null);
          },
          onError: (_) {
            // Realtime likely disabled for lf_items — keep the fetched feed.
          },
        );
  }

  List<LFItem> get _visible {
    final list =
        _items.values
            .where((i) => _filter == null || i.itemType == _filter)
            .toList()
          ..sort(
            (a, b) => (b.createdAt ?? b.eventDate).compareTo(
              a.createdAt ?? a.eventDate,
            ),
          );
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lost & Found')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.search_off,
                    label: 'I lost\nsomething',
                    color: NivaraColors.danger,
                    onTap: () => context.push(Routes.reportLost),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.inventory_2,
                    label: 'I found\nsomething',
                    color: NivaraColors.success,
                    onTap: () => context.push(Routes.reportFound),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Recent activity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _FilterChips(
                  value: _filter,
                  onChanged: (f) => setState(() => _filter = f),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _buildFeed()),
        ],
      ),
    );
  }

  Widget _buildFeed() {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _EmptyState(
        icon: Icons.cloud_off,
        title: 'Could not load items',
        subtitle: 'Realtime may be disabled for lf_items.\n$_error',
      );
    }
    final items = _visible;
    if (items.isEmpty) {
      return const _EmptyState(
        icon: Icons.travel_explore,
        title: 'Nothing here yet',
        subtitle: 'Be the first — report a lost or found item above.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final item = items[i];
        return LFItemCard(
          item: item,
          onTap: () => context.push(Routes.lostFoundMatch, extra: item),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.18),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.value, required this.onChanged});
  final LFItemType? value;
  final ValueChanged<LFItemType?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: [
        _chip(context, 'All', null),
        _chip(context, 'Lost', LFItemType.lost),
        _chip(context, 'Found', LFItemType.found),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, LFItemType? type) {
    final selected = value == type;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => onChanged(type),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
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
        ),
      ),
    );
  }
}
