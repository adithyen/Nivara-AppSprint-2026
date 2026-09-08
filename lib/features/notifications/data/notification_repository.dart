import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/services/debug_logger.dart';
import '../../../core/supabase_client.dart';
import '../../auth/auth_controller.dart';
import 'notification_model.dart';

/// Repository handling notification data access and live subscriptions.
class NotificationRepository {
  NotificationRepository();

  /// Streams notifications in realtime for the given user, ordered by creation date descending.
  Stream<List<AppNotification>> streamNotifications(String uid) {
    return supabase
        .from(kTableNotifications)
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .map((rows) {
          final list = <AppNotification>[];
          for (final row in rows) {
            try {
              list.add(AppNotification.fromMap(row));
            } catch (e) {
              DebugLogger.instance.log('NOTIF', 'Malformed notification row skipped: $e');
            }
          }
          return list;
        });
  }

  /// One-shot fetch of latest notifications.
  Future<List<AppNotification>> fetchNotifications(String uid, {int limit = 60}) async {
    try {
      final rows = await supabase
          .from(kTableNotifications)
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List)
          .map((r) => AppNotification.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      DebugLogger.instance.log('NOTIF', 'Error fetching notifications: $e');
      return [];
    }
  }

  /// Mark a single notification as read.
  Future<void> markAsRead(String notificationId) async {
    try {
      await supabase.from(kTableNotifications).update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      }).eq('id', notificationId);
    } catch (e) {
      DebugLogger.instance.log('NOTIF', 'Error marking notification read: $e');
    }
  }

  /// Mark all notifications for this user as read.
  Future<void> markAllAsRead(String uid) async {
    try {
      await supabase.from(kTableNotifications).update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String(),
      }).eq('user_id', uid).eq('is_read', false);
    } catch (e) {
      DebugLogger.instance.log('NOTIF', 'Error marking all notifications read: $e');
    }
  }

  /// Delete a single notification.
  Future<void> deleteNotification(String notificationId) async {
    try {
      await supabase.from(kTableNotifications).delete().eq('id', notificationId);
    } catch (e) {
      DebugLogger.instance.log('NOTIF', 'Error deleting notification: $e');
    }
  }

  /// Clear all notifications for the user.
  Future<void> clearAll(String uid) async {
    try {
      await supabase.from(kTableNotifications).delete().eq('user_id', uid);
    } catch (e) {
      DebugLogger.instance.log('NOTIF', 'Error clearing notifications: $e');
    }
  }
}

/// Provider for [NotificationRepository]
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository();
});

/// Realtime stream of the current user's notifications
final notificationsStreamProvider = StreamProvider.autoDispose<List<AppNotification>>((ref) {
  final user = ref.watch(authControllerProvider).asData?.value;
  if (user == null) {
    return const Stream.empty();
  }
  final repo = ref.watch(notificationRepositoryProvider);
  return repo.streamNotifications(user.id);
});

/// Unread notification count provider
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final notifsAsync = ref.watch(notificationsStreamProvider);
  return notifsAsync.maybeWhen(
    data: (list) => list.where((n) => !n.isRead).length,
    orElse: () => 0,
  );
});
