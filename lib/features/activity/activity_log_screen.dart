import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/enums.dart';
import '../../models/user_profile.dart';
import '../auth/auth_controller.dart';

// ── Activity entry model ────────────────────────────────────────────────────

enum ActivityCategory {
  report,
  sensorWatch,
  lostFound,
  confirmation,
  community,
  task,         // Worker: assigned task
  progressNote, // Worker: progress note submitted
  assignment,   // Admin: report assigned/acknowledged
  teamAction,   // Admin: hire/remove worker (from status_history)
}

class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.at,
    this.status,
  });

  final String id;
  final String title;
  final String subtitle;
  final ActivityCategory category;
  final DateTime at;
  final String? status;

  IconData get icon => switch (category) {
    ActivityCategory.report => Icons.report_problem_outlined,
    ActivityCategory.sensorWatch => Icons.sensors,
    ActivityCategory.lostFound => Icons.search,
    ActivityCategory.confirmation => Icons.thumb_up_outlined,
    ActivityCategory.community => Icons.groups_outlined,
    ActivityCategory.task => Icons.engineering,
    ActivityCategory.progressNote => Icons.note_outlined,
    ActivityCategory.assignment => Icons.assignment_turned_in_outlined,
    ActivityCategory.teamAction => Icons.manage_accounts,
  };

  Color color(BuildContext context) {
    return switch (category) {
      ActivityCategory.report => NivaraColors.danger,
      ActivityCategory.sensorWatch => NivaraColors.accent,
      ActivityCategory.lostFound => NivaraColors.primary,
      ActivityCategory.confirmation => NivaraColors.success,
      ActivityCategory.community => const Color(0xFF7B4BC4),
      ActivityCategory.task => NivaraColors.accent,
      ActivityCategory.progressNote => NivaraColors.success,
      ActivityCategory.assignment => NivaraColors.primary,
      ActivityCategory.teamAction => const Color(0xFF7B4BC4),
    };
  }
}

// ── Screen ─────────────────────────────────────────────────────────────────

/// **My Activity** — a per-role timeline of everything the signed-in user has
/// done in the app.
///
/// • Citizen: manual reports, sensor detections, L&F, confirmations, community
/// • Worker: same as citizen + assigned tasks + progress notes
/// • Admin: report assignments, community posts, team changes
class ActivityLogScreen extends ConsumerStatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  ConsumerState<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends ConsumerState<ActivityLogScreen> {
  List<ActivityEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final profile = ref.read(authControllerProvider).asData?.value;
    if (profile == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }

    try {
      final entries = await _fetch(profile);
      entries.sort((a, b) => b.at.compareTo(a.at));
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<List<ActivityEntry>> _fetch(UserProfile profile) async {
    final uid = profile.id;
    final entries = <ActivityEntry>[];

    // ── Citizen: Manual reports ──────────────────────────────────────────
    try {
      final reports = await supabase
          .from('reports')
          .select('id, category, title, status, created_at, source')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(50);

      for (final r in reports) {
        final isSensor = r['source'] == 'SENSORWATCH';
        final cat = _parseEnum(r['category'] as String?, ReportCategory.values) as ReportCategory?;
        entries.add(ActivityEntry(
          id: r['id'] as String,
          title: isSensor ? '🔊 Sensor Detection' : '📋 Manual Report',
          subtitle: (r['title'] as String?) ??
              (cat?.label ?? (r['category'] as String? ?? 'Issue')),
          category: isSensor
              ? ActivityCategory.sensorWatch
              : ActivityCategory.report,
          at: DateTime.parse(r['created_at'] as String),
          status: r['status'] as String?,
        ));
      }
    } catch (_) {}

    // ── Citizen: L&F items ──────────────────────────────────────────────
    try {
      final lfItems = await supabase
          .from('lf_items')
          .select('id, item_type, title, created_at')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(30);

      for (final lf in lfItems) {
        entries.add(ActivityEntry(
          id: lf['id'] as String,
          title: lf['item_type'] == 'LOST' ? '🔍 Lost Report' : '📦 Found Report',
          subtitle: lf['title'] as String? ?? 'L&F item',
          category: ActivityCategory.lostFound,
          at: DateTime.parse(lf['created_at'] as String),
        ));
      }
    } catch (_) {}

    // ── Citizen: Confirmations ───────────────────────────────────────────
    try {
      final confirms = await supabase
          .from('confirmations')
          .select('id, type, created_at, report_id')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(30);

      for (final c in confirms) {
        entries.add(ActivityEntry(
          id: c['id'] as String,
          title: c['type'] == 'CONFIRM' ? '👍 Confirmed a report' : '🚩 Disputed a report',
          subtitle: 'Report ID: ${(c['report_id'] as String).substring(0, 8)}…',
          category: ActivityCategory.confirmation,
          at: DateTime.parse(c['created_at'] as String),
        ));
      }
    } catch (_) {}

    // ── Citizen: Community posts ─────────────────────────────────────────
    try {
      final posts = await supabase
          .from('community_posts')
          .select('id, post_type, title, created_at')
          .eq('author_id', uid)
          .order('created_at', ascending: false)
          .limit(30);

      for (final p in posts) {
        final postType = p['post_type'] as String? ?? 'GENERAL';
        entries.add(ActivityEntry(
          id: p['id'] as String,
          title: '💬 Community Post',
          subtitle: (p['title'] as String?)?.isNotEmpty == true
              ? p['title'] as String
              : postType,
          category: ActivityCategory.community,
          at: DateTime.parse(p['created_at'] as String),
        ));
      }
    } catch (_) {}

    // ── Worker extras ────────────────────────────────────────────────────
    if (profile.isWorker) {
      // Assigned tasks
      try {
        final tasks = await supabase
            .from('reports')
            .select('id, category, title, status, updated_at')
            .eq('assigned_to', uid)
            .order('updated_at', ascending: false)
            .limit(30);

        for (final t in tasks) {
          final cat = _parseEnum(t['category'] as String?, ReportCategory.values) as ReportCategory?;
          entries.add(ActivityEntry(
            id: '${t['id']}_task',
            title: '🔧 Task Assigned',
            subtitle: (t['title'] as String?) ?? cat?.label ?? 'Task',
            category: ActivityCategory.task,
            at: DateTime.parse(t['updated_at'] as String),
            status: t['status'] as String?,
          ));
        }
      } catch (_) {}

      // Progress notes
      try {
        final notes = await supabase
            .from('worker_progress_notes')
            .select('id, report_id, note, created_at')
            .eq('worker_id', uid)
            .order('created_at', ascending: false)
            .limit(30);

        for (final n in notes) {
          entries.add(ActivityEntry(
            id: n['id'] as String,
            title: '📝 Progress Note',
            subtitle: (n['note'] as String? ?? '').length > 60
                ? '${(n['note'] as String).substring(0, 60)}…'
                : n['note'] as String? ?? '',
            category: ActivityCategory.progressNote,
            at: DateTime.parse(n['created_at'] as String),
          ));
        }
      } catch (_) {}
    }

    // ── Admin extras ─────────────────────────────────────────────────────
    if (profile.isAdmin) {
      // Assignments / status changes made by this admin
      try {
        final history = await supabase
            .from('report_status_history')
            .select('id, report_id, new_status, created_at')
            .eq('changed_by', uid)
            .order('created_at', ascending: false)
            .limit(50);

        for (final h in history) {
          final status = h['new_status'] as String? ?? '';
          entries.add(ActivityEntry(
            id: h['id'] as String,
            title: _adminActionTitle(status),
            subtitle: 'Report: ${(h['report_id'] as String).substring(0, 8)}…',
            category: ActivityCategory.assignment,
            at: DateTime.parse(h['created_at'] as String),
            status: status,
          ));
        }
      } catch (_) {}
    }

    return entries;
  }

  String _adminActionTitle(String status) => switch (status.toUpperCase()) {
    'ACKNOWLEDGED' => '✅ Acknowledged report',
    'IN_PROGRESS' => '🔨 Assigned to worker',
    'RESOLVED' => '🏁 Marked resolved',
    _ => '📋 Status update',
  };

  dynamic _parseEnum(String? value, List<Enum> values) {
    if (value == null) return null;
    try {
      return values.firstWhere(
        (e) => e.name.toUpperCase() == value.toUpperCase(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Activity'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorView(message: _error!, onRetry: _load)
          : _entries.isEmpty
          ? const _EmptyView()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: _entries.length,
                itemBuilder: (_, i) {
                  final prev = i > 0 ? _entries[i - 1] : null;
                  final entry = _entries[i];
                  final showDate = prev == null ||
                      !_sameDay(prev.at, entry.at);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showDate) _DateHeader(entry.at),
                      _ActivityTile(entry: entry),
                    ],
                  );
                },
              ),
            ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ── Sub-widgets ───────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  const _DateHeader(this.date);
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final label = d == today
        ? 'Today'
        : d == today.subtract(const Duration(days: 1))
            ? 'Yesterday'
            : _fmt(date);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.entry});
  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = entry.color(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF10161E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Icon(entry.icon, color: color, size: 20),
        ),
        title: Text(
          entry.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              entry.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              timeAgo(entry.at),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        trailing: entry.status != null
            ? _StatusBadge(entry.status!)
            : null,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);
  final String status;

  Color _color() => switch (status.toUpperCase()) {
    'RESOLVED' => NivaraColors.success,
    'IN_PROGRESS' => NivaraColors.primaryBlue,
    'ACKNOWLEDGED' => NivaraColors.accent,
    _ => Colors.white60,
  };

  @override
  Widget build(BuildContext context) {
    final c = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          color: c,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No activity yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Your reports, posts, and tasks will appear here.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
