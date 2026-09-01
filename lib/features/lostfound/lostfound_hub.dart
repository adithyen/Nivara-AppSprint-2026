import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../models/enums.dart';
import '../../models/lf_item.dart';
import '../../router.dart';
import 'item_card.dart';

/// 2026-Level Flagship Lost & Found Hub.
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
  LFItemType? _filter;

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

  Future<void> _load() async {
    try {
      final rows = await supabase
          .from(kTableLfItems)
          .select()
          .eq('status', 'ACTIVE')
          .order('created_at', ascending: false);
      final newItems = <String, LFItem>{};
      for (final r in rows) {
        try {
          final item = LFItem.fromMap(r);
          if (item.status == 'ACTIVE') {
            newItems[item.id] = item;
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(newItems);
          _loaded = true;
          _error = null;
        });
      }
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
    _sub?.cancel();
    _sub = supabase
        .from(kTableLfItems)
        .stream(primaryKey: ['id'])
        .order('created_at')
        .listen(
          (rows) {
            bool changed = false;
            for (final r in rows) {
              try {
                final item = LFItem.fromMap(r);
                if (item.status == 'ACTIVE') {
                  if (_items[item.id] != item) {
                    _items[item.id] = item;
                    changed = true;
                  }
                } else {
                  if (_items.containsKey(item.id)) {
                    _items.remove(item.id);
                    changed = true;
                  }
                }
              } catch (_) {}
            }
            if (mounted && changed) setState(() => _error = null);
          },
          onError: (_) {},
        );
  }

  List<LFItem> get _visible {
    final uid = currentUserId;
    final list = _items.values
        .where((i) {
          if (i.status != 'ACTIVE') return false;
          if (_filter != null && i.itemType != _filter) return false;
          // Hide private items from public explore feed unless owned by current user
          if (i.isPrivate && (uid == null || i.userId != uid)) return false;
          return true;
        })
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
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lost & Found Radar'),
        actions: [
          IconButton(
            tooltip: 'My listings',
            icon: const Icon(Icons.inbox_outlined),
            onPressed: () async {
              await context.push(Routes.myListings);
              if (mounted) _load();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.search_off_rounded,
                    label: 'I Lost\nSomething',
                    color: NivaraColors.danger,
                    onTap: () async {
                      await context.push(Routes.reportLost);
                      if (mounted) _load();
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.inventory_2_rounded,
                    label: 'I Found\nSomething',
                    color: primary,
                    onTap: () async {
                      await context.push(Routes.reportFound);
                      if (mounted) _load();
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Active Listings',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
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
    final primary = Theme.of(context).colorScheme.primary;

    if (!_loaded) {
      return Center(child: CircularProgressIndicator(color: primary));
    }
    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load items',
              subtitle: 'Check network connection or pull down to retry.\n$_error',
            ),
          ],
        ),
      );
    }
    final items = _visible;
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            _EmptyState(
              icon: Icons.travel_explore_rounded,
              title: 'No Active Listings',
              subtitle: 'Be the first — report a lost or found item above.\nPull down to refresh.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final item = items[i];
          return LFItemCard(
            item: item,
            onTap: () async {
              await context.push(Routes.lostFoundDetail, extra: item);
              if (mounted) _load();
            },
          );
        },
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BouncyTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF10161E) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.35 : 0.3),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: isDark ? 0.12 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.16 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                height: 1.2,
              ),
            ),
          ],
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
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BouncyTap(
      onTap: () => onChanged(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: isDark ? 0.2 : 0.15)
              : (isDark ? const Color(0xFF131A24) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? primary
                : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? primary
                : (isDark ? Colors.white70 : const Color(0xFF4B5563)),
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
              ),
              child: Icon(
                icon,
                size: 48,
                color: isDark ? Colors.white38 : Colors.black26,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF111827),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF6B7280),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
