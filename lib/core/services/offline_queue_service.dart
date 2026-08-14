import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../core/constants.dart';
import '../../core/supabase_client.dart';

// ── SharedPreferences keys ─────────────────────────────────────────────────
const _kReports = 'offline_queue_reports';
const _kLfItems = 'offline_queue_lf_items';
const _kCommunity = 'offline_queue_community';
const _kConfirms = 'offline_queue_confirmations';
const _kWorkerNotes = 'offline_queue_worker_notes';


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

  /// 'report' | 'lf_item' | 'community' | 'confirmation' | 'worker_note'
  final String type;

  /// JSON-encodable map of the insert data.
  final Map<String, dynamic> payload;

  /// Paths to local temp copies of photos (may be empty).
  final List<String> localPhotoPaths;

  /// Set to true on drain when a photo file is missing — shown in the UI
  /// so the user knows to resubmit with the photo.
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

/// Static-only service for offline queuing.
///
/// **Enqueue flow (when offline):**
///   1. Copy any picked photos to `getTemporaryDirectory()/nivara_queue/<uuid>/`
///   2. Store a `QueueEntry` JSON in SharedPreferences under the type's key.
///
/// **Drain flow (when online):**
///   1. Read all keys; for each entry attempt the Supabase insert.
///   2. If a local photo path exists and the file is present, upload it first.
///   3. If the file is missing, mark `hasPhotoError = true` and re-persist so
///      the UI can warn the user to resubmit with their photo.
///   4. On successful insert, remove from queue.
class OfflineQueueService {
  OfflineQueueService._();

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
  }) async {
    final entry = await _buildEntry('community', payload, []);
    await _append(_kCommunity, entry);
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
      _kConfirms,
      _kWorkerNotes,
    ]) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      final list = jsonDecode(raw) as List;
      all.addAll(list.map((e) => QueueEntry.fromJson(e as Map<String, dynamic>)));
    }
    return all;
  }

  static Future<int> pendingCount() async => (await allPending()).length;

  // ── Drain ─────────────────────────────────────────────────────────────────

  /// Tries to submit all queued entries to Supabase.
  /// Returns the number of entries that were successfully synced.
  static Future<int> drainAll() async {
    final prefs = await SharedPreferences.getInstance();
    var synced = 0;

    for (final key in [
      _kReports,
      _kLfItems,
      _kCommunity,
      _kConfirms,
      _kWorkerNotes,
    ]) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      final list = (jsonDecode(raw) as List)
          .map((e) => QueueEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      final remaining = <QueueEntry>[];

      for (final entry in list) {
        try {
          // Try to upload photos from temp storage first
          final photoUrls = <String>[];
          bool photoMissing = false;
          for (final path in entry.localPhotoPaths) {
            final file = File(path);
            if (await file.exists()) {
              final uid = supabase.auth.currentUser?.id ?? 'anon';
              final stamp = DateTime.now().millisecondsSinceEpoch;
              final storagePath = '$uid/${stamp}_offline.jpg';
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

          // Build the final payload (inject uploaded photo URLs)
          final finalPayload = Map<String, dynamic>.from(entry.payload);
          if (photoUrls.isNotEmpty) {
            finalPayload['photo_urls'] = photoUrls;
          }

          // Insert into Supabase
          final table = _tableFor(entry.type);
          if (table != null) {
            await supabase.from(table).insert(finalPayload);
          }

          synced++;

          // If some photos were missing, re-add with a flag instead of dropping
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
        } catch (_) {
          // If insert failed (still offline?), keep in queue
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

    return synced;
  }

  /// Remove a single entry (e.g. after user dismisses a photo-error notice).
  static Future<void> removeEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      _kReports,
      _kLfItems,
      _kCommunity,
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
      final tmpDir = await getTemporaryDirectory();
      final queueDir = Directory('${tmpDir.path}/nivara_queue/$id');
      await queueDir.create(recursive: true);
      for (var i = 0; i < photos.length; i++) {
        final dest = '${queueDir.path}/photo_$i.jpg';
        await photos[i].copy(dest);
        paths.add(dest);
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
