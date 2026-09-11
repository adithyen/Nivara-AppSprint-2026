import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/offline_queue_service.dart';
import '../../core/theme.dart';
import '../settings/language_controller.dart';

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
    final currentLang = ref.read(languageControllerProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(NivaraStrings.tr('pending_sync_clear_title', currentLang)),
        content: Text(NivaraStrings.tr('pending_sync_clear_body', currentLang)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(NivaraStrings.tr('sign_out_cancel', currentLang)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NivaraColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(NivaraStrings.tr('pending_sync_clear', currentLang)),
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
    final currentLang = ref.watch(languageControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(NivaraStrings.tr('pending_sync_title', currentLang)),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: NivaraStrings.tr('pending_sync_clear', currentLang),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearAll,
            ),
          IconButton(
            tooltip: NivaraStrings.tr('pending_sync_refresh', currentLang),
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? _EmptyView(onRefresh: _load, currentLang: currentLang)
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  // Summary banner
                  _SummaryBanner(count: _entries.length, currentLang: currentLang),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      itemCount: _entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _QueueTile(
                        entry: _entries[i],
                        currentLang: currentLang,
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
              label: Text(_draining
                  ? NivaraStrings.tr('pending_sync_syncing', currentLang)
                  : NivaraStrings.tr('pending_sync_now', currentLang)),
              backgroundColor:
                  _draining ? Colors.grey : NivaraColors.primary,
            )
          : null,
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.count, required this.currentLang});
  final int count;
  final AppLanguage currentLang;

  @override
  Widget build(BuildContext context) {
    final titleText = switch (currentLang) {
      AppLanguage.ml => '$count ഇനങ്ങൾ സിങ്ക് ചെയ്യാൻ കാത്തിരിക്കുന്നു',
      AppLanguage.hi => '$count आइटम सिंक के लिए कतार में',
      _ => '$count item${count == 1 ? '' : 's'} waiting to sync',
    };

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
                  titleText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: NivaraColors.accent,
                  ),
                ),
                Text(
                  NivaraStrings.tr('pending_sync_banner_sub', currentLang),
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
  const _QueueTile({
    required this.entry,
    required this.currentLang,
    required this.onDismiss,
  });
  final QueueEntry entry;
  final AppLanguage currentLang;
  final VoidCallback onDismiss;

  String get _typeLabel => switch (entry.type) {
    'report' => 'Civic Report',
    'lf_item' => 'Lost & Found Item',
    'community' => 'Community Post',
    'confirmation' => 'Civic Confirmation',
    'worker_note' => 'Field Progress Note',
    _ when entry.type.endsWith('_photo_error') => 'Photo Missing',
    _ => entry.type,
  };

  IconData get _typeIcon => switch (entry.type) {
    'report' => Icons.report_problem_rounded,
    'lf_item' => Icons.search_rounded,
    'community' => Icons.groups_rounded,
    'confirmation' => Icons.thumb_up_rounded,
    'worker_note' => Icons.note_rounded,
    _ => Icons.cloud_off_rounded,
  };
  bool get _isPhotoError => entry.hasPhotoError;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _isPhotoError ? NivaraColors.danger : NivaraColors.accent;
    final fmt = DateFormat('d MMM · HH:mm');

    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: NivaraColors.danger.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: NivaraColors.danger),
      ),
      onDismissed: (_) => onDismiss(),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF10161E) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _isPhotoError
                ? NivaraColors.danger.withValues(alpha: 0.45)
                : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(_typeIcon, color: color, size: 20),
              ),
              title: Text(
                _typeLabel,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                '${NivaraStrings.tr('pending_sync_queued_prefix', currentLang)} ${fmt.format(entry.queuedAt)}',
                style: TextStyle(
                  color: isDark ? Colors.white.withValues(alpha: 0.55) : const Color(0xFF64748B),
                  fontSize: 12,
                ),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (entry.localPhotoPaths.isNotEmpty
                          ? NivaraColors.primary
                          : (isDark ? Colors.white60 : const Color(0xFF94A3B8)))
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (entry.localPhotoPaths.isNotEmpty
                            ? NivaraColors.primary
                            : (isDark ? Colors.white60 : const Color(0xFF94A3B8)))
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  entry.localPhotoPaths.isNotEmpty
                      ? NivaraStrings.tr('pending_sync_with_photo', currentLang)
                      : NivaraStrings.tr('pending_sync_text_only', currentLang),
                  style: TextStyle(
                    color: entry.localPhotoPaths.isNotEmpty
                        ? NivaraColors.primary
                        : (isDark ? Colors.white70 : const Color(0xFF475569)),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (_isPhotoError)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: NivaraColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: NivaraColors.danger.withValues(alpha: 0.35),
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
                    Expanded(
                      child: Text(
                        NivaraStrings.tr('pending_sync_photo_error', currentLang),
                        style: const TextStyle(
                          color: NivaraColors.danger,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
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
  const _EmptyView({required this.onRefresh, required this.currentLang});
  final VoidCallback onRefresh;
  final AppLanguage currentLang;

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
            NivaraStrings.tr('pending_sync_empty_title', currentLang),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: NivaraColors.success,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            NivaraStrings.tr('pending_sync_empty_sub', currentLang),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: Text(NivaraStrings.tr('pending_sync_refresh', currentLang)),
          ),
        ],
      ),
    );
  }
}
