import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/services/offline_queue_service.dart';
import '../../core/theme.dart';

/// **Pending Sync** — shows everything queued offline waiting to sync.
///
/// Items that failed due to a missing photo get a special "Photo missing"
/// banner prompting the user to resubmit with the photo manually.
class PendingSyncScreen extends ConsumerStatefulWidget {
  const PendingSyncScreen({super.key});

  @override
  ConsumerState<PendingSyncScreen> createState() => _PendingSyncScreenState();
}

class _PendingSyncScreenState extends ConsumerState<PendingSyncScreen> {
  List<QueueEntry> _entries = [];
  bool _loading = true;
  bool _draining = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await OfflineQueueService.allPending();
    if (!mounted) return;
    setState(() {
      _entries = all;
      _loading = false;
    });
  }

  Future<void> _drain() async {
    setState(() => _draining = true);
    final synced = await OfflineQueueService.drainAll();
    await _load();
    if (!mounted) return;
    setState(() => _draining = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          synced == 0
              ? 'Nothing to sync — check your connection.'
              : 'Synced $synced item${synced == 1 ? '' : 's'} successfully.',
        ),
      ),
    );
  }

  Future<void> _remove(String id) async {
    await OfflineQueueService.removeEntry(id);
    await _load();
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear pending sync?'),
        content: const Text(
          'All queued items will be discarded and will NOT be submitted. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NivaraColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await OfflineQueueService.clearAll();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Sync'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: 'Clear all',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearAll,
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? _EmptyView(onRefresh: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  // Summary banner
                  _SummaryBanner(count: _entries.length),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      itemCount: _entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _QueueTile(
                        entry: _entries[i],
                        onDismiss: () => _remove(_entries[i].id),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: _entries.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _draining ? null : _drain,
              icon: _draining
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(_draining ? 'Syncing…' : 'Sync now'),
              backgroundColor:
                  _draining ? Colors.grey : NivaraColors.primary,
            )
          : null,
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: NivaraColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NivaraColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: NivaraColors.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count item${count == 1 ? '' : 's'} waiting to sync',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: NivaraColors.accent,
                  ),
                ),
                Text(
                  'These will be submitted automatically when you\'re back online.',
                  style: TextStyle(
                    color: NivaraColors.accent.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.entry, required this.onDismiss});
  final QueueEntry entry;
  final VoidCallback onDismiss;

  String get _typeLabel => switch (entry.type) {
    'report' => 'Manual Report',
    'lf_item' => 'Lost & Found',
    'community' => 'Community Post',
    'confirmation' => 'Confirmation',
    'worker_note' => 'Progress Note',
    _ when entry.type.endsWith('_photo_error') => 'Photo Missing',
    _ => entry.type,
  };

  IconData get _typeIcon => switch (entry.type) {
    'report' => Icons.report_problem_outlined,
    'lf_item' => Icons.search,
    'community' => Icons.groups_outlined,
    'confirmation' => Icons.thumb_up_outlined,
    'worker_note' => Icons.note_outlined,
    _ => Icons.cloud_off,
  };

  bool get _isPhotoError => entry.hasPhotoError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _isPhotoError ? NivaraColors.danger : NivaraColors.accent;
    final fmt = DateFormat('d MMM · HH:mm');

    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: NivaraColors.danger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: NivaraColors.danger),
      ),
      onDismissed: (_) => onDismiss(),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isPhotoError
                ? NivaraColors.danger.withValues(alpha: 0.4)
                : scheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(_typeIcon, color: color, size: 18),
              ),
              title: Text(
                _typeLabel,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: Text(
                'Queued ${fmt.format(entry.queuedAt)}',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              trailing: Chip(
                label: Text(
                  entry.localPhotoPaths.isNotEmpty ? '📷 +photo' : 'Text only',
                  style: const TextStyle(fontSize: 11),
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
            // Photo error warning
            if (_isPhotoError)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: NivaraColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: NivaraColors.danger.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.photo_camera_outlined,
                      color: NivaraColors.danger,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Photo was cleared from temp storage. '
                        'This item was submitted without the photo — '
                        'please resubmit with a new photo if needed.',
                        style: TextStyle(
                          color: NivaraColors.danger,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_done_outlined,
            size: 72,
            color: NivaraColors.success.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          Text(
            'All synced!',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: NivaraColors.success,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No pending items. Everything has been submitted.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}
