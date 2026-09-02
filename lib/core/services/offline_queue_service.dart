import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../models/community_poll.dart';
import '../../models/community_post.dart';

// ── SharedPreferences keys ─────────────────────────────────────────────────
const _kReports = 'offline_queue_reports';
const _kLfItems = 'offline_queue_lf_items';
const _kCommunity = 'offline_queue_community';
const _kWorkerApps = 'offline_queue_worker_apps';
const _kConfirms = 'offline_queue_confirmations';
const _kWorkerNotes = 'offline_queue_worker_notes';

// ── Sync Event Notifier ───────────────────────────────────────────────────

enum SyncStatusState { idle, syncing, completed, error }

class SyncEvent {
  final SyncStatusState state;
  final int total;
  final int synced;
  final String? message;

  const SyncEvent({
    required this.state,
    this.total = 0,
    this.synced = 0,
    this.message,
  });
}

final ValueNotifier<SyncEvent> syncNotifier =
    ValueNotifier<SyncEvent>(const SyncEvent(state: SyncStatusState.idle));

// ── Offline queue entry ────────────────────────────────────────────────────

/// A single queued action with enough data to replay it when back online.
class QueueEntry {
  QueueEntry({
    required this.id,
    required this.type,
    required this.payload,
    required this.queuedAt,
    this.localPhotoPaths = const [],
    this.hasPhotoError = false,
  });

  /// UUID generated client-side so we can deduplicate on drain.
  final String id;

  /// 'report' | 'lf_item' | 'community' | 'worker_application' | 'confirmation' | 'worker_note'
  final String type;

  /// JSON-encodable map of the insert data.
  final Map<String, dynamic> payload;

  /// Paths to local temp copies of photos (may be empty).
  final List<String> localPhotoPaths;

  /// Set to true on drain when a photo file is missing.
  final bool hasPhotoError;

  final DateTime queuedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'payload': payload,
    'localPhotoPaths': localPhotoPaths,
    'hasPhotoError': hasPhotoError,
    'queuedAt': queuedAt.toIso8601String(),
  };

  factory QueueEntry.fromJson(Map<String, dynamic> j) => QueueEntry(
    id: j['id'] as String,
    type: j['type'] as String,
    payload: Map<String, dynamic>.from(j['payload'] as Map),
    localPhotoPaths: List<String>.from(j['localPhotoPaths'] ?? []),
    hasPhotoError: j['hasPhotoError'] as bool? ?? false,
    queuedAt: DateTime.parse(j['queuedAt'] as String),
  );
}

// ── Service ────────────────────────────────────────────────────────────────

class OfflineQueueService {
  OfflineQueueService._();

  static bool _isDraining = false;

  // ── Enqueue ──────────────────────────────────────────────────────────────

  static Future<void> enqueueReport({
    required Map<String, dynamic> payload,
    List<File> photos = const [],
  }) async {
    final entry = await _buildEntry('report', payload, photos);
    await _append(_kReports, entry);
  }

  static Future<void> enqueueLfItem({
    required Map<String, dynamic> payload,
    List<File> photos = const [],
  }) async {
    final entry = await _buildEntry('lf_item', payload, photos);
    await _append(_kLfItems, entry);
  }

  static Future<void> enqueueCommunity({
    required Map<String, dynamic> payload,
    List<File> photos = const [],
  }) async {
    final entry = await _buildEntry('community', payload, photos);
    await _append(_kCommunity, entry);
  }

  static Future<void> enqueueWorkerApplication({
    required Map<String, dynamic> payload,
  }) async {
    final entry = await _buildEntry('worker_application', payload, []);
    await _append(_kWorkerApps, entry);
  }

  static Future<void> enqueueConfirmation({
    required Map<String, dynamic> payload,
  }) async {
    final entry = await _buildEntry('confirmation', payload, []);
    await _append(_kConfirms, entry);
  }

  static Future<void> enqueueWorkerNote({
    required Map<String, dynamic> payload,
  }) async {
    final entry = await _buildEntry('worker_note', payload, []);
    await _append(_kWorkerNotes, entry);
  }

  // ── Read ─────────────────────────────────────────────────────────────────

  static Future<List<QueueEntry>> allPending() async {
    final prefs = await SharedPreferences.getInstance();
    final all = <QueueEntry>[];
    for (final key in [
      _kReports,
      _kLfItems,
      _kCommunity,
      _kWorkerApps,
      _kConfirms,
      _kWorkerNotes,
    ]) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final list = jsonDecode(raw) as List;
        all.addAll(list.map((e) => QueueEntry.fromJson(e as Map<String, dynamic>)));
      } catch (_) {}
    }
    return all;
  }

  static Future<int> pendingCount() async => (await allPending()).length;

  // ── Drain ─────────────────────────────────────────────────────────────────

  /// Tries to submit all queued entries to Supabase.
  /// Returns the number of entries that were successfully synced.
  static Future<int> drainAll() async {
    if (_isDraining) return 0;
    _isDraining = true;

    try {
      final all = await allPending();
      if (all.isEmpty) {
        _isDraining = false;
        return 0;
      }

      final prefs = await SharedPreferences.getInstance();
      var synced = 0;
      final total = all.length;

      syncNotifier.value = SyncEvent(
        state: SyncStatusState.syncing,
        total: total,
        synced: 0,
        message: 'Syncing $total offline item${total > 1 ? 's' : ''}...',
      );

      for (final key in [
        _kReports,
        _kLfItems,
        _kCommunity,
        _kWorkerApps,
        _kConfirms,
        _kWorkerNotes,
      ]) {
        final raw = prefs.getString(key);
        if (raw == null) continue;

        List<QueueEntry> list;
        try {
          list = (jsonDecode(raw) as List)
              .map((e) => QueueEntry.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (_) {
          continue;
        }

        final remaining = <QueueEntry>[];

        for (final entry in list) {
          try {
            final uid = supabase.auth.currentUser?.id;

            // 1. Upload photos from local temp storage if available
            final photoUrls = <String>[];
            bool photoMissing = false;
            for (final path in entry.localPhotoPaths) {
              final file = File(path);
              if (await file.exists()) {
                final userFolder = uid ?? 'anon';
                final stamp = DateTime.now().millisecondsSinceEpoch;
                final storagePath = '$userFolder/${stamp}_offline.jpg';
                final bytes = await file.readAsBytes();
                await supabase.storage.from(kBucketPhotos).uploadBinary(
                  storagePath,
                  bytes,
                  fileOptions: const FileOptions(
                    contentType: 'image/jpeg',
                    upsert: true,
                  ),
                );
                photoUrls.add(
                  supabase.storage.from(kBucketPhotos).getPublicUrl(storagePath),
                );
              } else {
                photoMissing = true;
              }
            }

            // 2. Prepare payload
            final finalPayload = Map<String, dynamic>.from(entry.payload);
            if (photoUrls.isNotEmpty) {
              final existingPhotos = finalPayload['photo_urls'];
              if (existingPhotos is List) {
                finalPayload['photo_urls'] = [...existingPhotos, ...photoUrls];
              } else {
                finalPayload['photo_urls'] = photoUrls;
              }
            }

            // 3. Entity-specific sync logic
            if (entry.type == 'worker_application') {
              final msg = finalPayload['message'] as String? ?? jsonEncode(finalPayload);
              await supabase.rpc('submit_worker_application', params: {'p_message': msg});
            } else if (entry.type == 'community') {
              if (uid != null) {
                finalPayload['author_id'] = uid;
              }
              final pollOptions = finalPayload.remove('poll_options');
              final row = await supabase
                  .from(kTableCommunityPosts)
                  .insert(finalPayload)
                  .select()
                  .single();

              if (pollOptions is List && pollOptions.isNotEmpty) {
                final post = CommunityPost.fromMap(row);
                await supabase.from(kTableCommunityPollOptions).insert([
                  for (var i = 0; i < pollOptions.length; i++)
                    CommunityPollOption(
                      id: '',
                      postId: post.id,
                      label: pollOptions[i] as String,
                      position: i,
                    ).toInsertMap(),
                ]);
              }
            } else {
              // Ensure user_id matches active auth user for RLS policies
              if (uid != null) {
                if (finalPayload.containsKey('user_id')) {
                  finalPayload['user_id'] = uid;
                }
              }

              final table = _tableFor(entry.type);
              if (table != null) {
                await supabase.from(table).insert(finalPayload);
              }
            }

            synced++;
            syncNotifier.value = SyncEvent(
              state: SyncStatusState.syncing,
              total: total,
              synced: synced,
              message: 'Syncing $synced/$total items...',
            );

            // If some photos were missing from disk, keep a placeholder error
            if (photoMissing && entry.localPhotoPaths.isNotEmpty) {
              remaining.add(
                QueueEntry(
                  id: '${entry.id}_photo_error',
                  type: '${entry.type}_photo_error',
                  payload: entry.payload,
                  localPhotoPaths: const [],
                  hasPhotoError: true,
                  queuedAt: entry.queuedAt,
                ),
              );
            }
          } catch (e) {
            debugPrint('[OfflineQueue] Failed to sync ${entry.id} (${entry.type}): $e');
            remaining.add(entry);
          }
        }

        if (remaining.isEmpty) {
          await prefs.remove(key);
        } else {
          await prefs.setString(
            key,
            jsonEncode(remaining.map((e) => e.toJson()).toList()),
          );
        }
      }

      if (synced > 0) {
        syncNotifier.value = SyncEvent(
          state: SyncStatusState.completed,
          total: total,
          synced: synced,
          message: 'Synced $synced offline item${synced > 1 ? 's' : ''} successfully.',
        );
        Future.delayed(const Duration(seconds: 4), () {
          if (syncNotifier.value.state == SyncStatusState.completed) {
            syncNotifier.value = const SyncEvent(state: SyncStatusState.idle);
          }
        });
      } else {
        syncNotifier.value = const SyncEvent(state: SyncStatusState.idle);
      }

      _isDraining = false;
      return synced;
    } catch (err) {
      debugPrint('[OfflineQueue] Drain exception: $err');
      _isDraining = false;
      syncNotifier.value = SyncEvent(
        state: SyncStatusState.error,
        message: 'Could not sync all items: $err',
      );
      return 0;
    }
  }

  /// Remove a single entry (e.g. after user dismisses a photo-error notice).
  static Future<void> removeEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      _kReports,
      _kLfItems,
      _kCommunity,
      _kWorkerApps,
      _kConfirms,
      _kWorkerNotes,
    ]) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      final list = (jsonDecode(raw) as List)
          .map((e) => QueueEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      final filtered = list.where((e) => e.id != entryId).toList();
      if (filtered.length == list.length) continue;
      if (filtered.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(
          key,
          jsonEncode(filtered.map((e) => e.toJson()).toList()),
        );
      }
      break;
    }
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      _kReports,
      _kLfItems,
      _kCommunity,
      _kWorkerApps,
      _kConfirms,
      _kWorkerNotes,
    ]) {
      await prefs.remove(key);
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  static Future<QueueEntry> _buildEntry(
    String type,
    Map<String, dynamic> payload,
    List<File> photos,
  ) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final paths = <String>[];

    if (photos.isNotEmpty) {
      try {
        final tmpDir = await getTemporaryDirectory();
        final queueDir = Directory('${tmpDir.path}/nivara_queue/$id');
        await queueDir.create(recursive: true);
        for (var i = 0; i < photos.length; i++) {
          final dest = '${queueDir.path}/photo_$i.jpg';
          await photos[i].copy(dest);
          paths.add(dest);
        }
      } catch (e) {
        debugPrint('[OfflineQueue] Could not cache photos: $e');
      }
    }

    return QueueEntry(
      id: id,
      type: type,
      payload: payload,
      localPhotoPaths: paths,
      queuedAt: DateTime.now(),
    );
  }

  static String? _tableFor(String type) => switch (type) {
    'report' => kTableReports,
    'lf_item' => kTableLfItems,
    'community' => kTableCommunityPosts,
    'worker_application' => 'worker_applications',
    'confirmation' => kTableConfirmations,
    'worker_note' => 'worker_progress_notes',
    _ => null,
  };

  static Future<void> _append(String key, QueueEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    final list = raw == null
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List)
            .cast<Map<String, dynamic>>()
            .toList();
    list.add(entry.toJson());
    await prefs.setString(key, jsonEncode(list));
  }
}
