import 'package:flutter/material.dart';

import '../../../core/utils.dart';

/// Represents an in-app notification row in the `notifications` table.
class AppNotification {
  final String id;
  final String userId;
  final String title;
  final String body;
  final String type;
  final Map<String, dynamic> payload;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    required this.payload,
    required this.isRead,
    required this.createdAt,
    this.readAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      title: map['title'] as String? ?? 'Notification',
      body: map['body'] as String? ?? '',
      type: map['type'] as String? ?? 'SYSTEM',
      payload: (map['payload'] is Map)
          ? Map<String, dynamic>.from(map['payload'] as Map)
          : <String, dynamic>{},
      isRead: (map['is_read'] as bool?) ?? false,
      createdAt: toDateTimeOrNull(map['created_at']) ?? DateTime.now(),
      readAt: toDateTimeOrNull(map['read_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'body': body,
      'type': type,
      'payload': payload,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
    };
  }

  AppNotification copyWith({
    bool? isRead,
    DateTime? readAt,
  }) {
    return AppNotification(
      id: id,
      userId: userId,
      title: title,
      body: body,
      type: type,
      payload: payload,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
    );
  }

  /// Categorize for filtering in Notification Center
  String get category {
    switch (type) {
      case 'REPORT_ACKNOWLEDGED':
      case 'WORKER_ASSIGNED':
      case 'WORKER_PROGRESS_NOTE':
      case 'REPORT_RESOLVED':
      case 'REPORT_REJECTED':
      case 'NEW_REPORT':
        return 'reports';

      case 'WORK_ASSIGNED':
      case 'ADMIN_PROGRESS_REQUEST':
        return 'work';

      case 'LF_MATCH':
      case 'LF_CLAIM_RECEIVED':
      case 'LF_HANDOVER_INTENT':
      case 'LF_HANDOVER_COMPLETED':
        return 'lostfound';

      case 'COMMUNITY_ANNOUNCEMENT':
      case 'COMMUNITY_POST':
      case 'NEW_COMMUNITY_POST':
        return 'community';

      case 'WORKER_LEAVE':
      case 'WORKER_RESIGNED':
      case 'NEW_WORKER_APPLICATION':
      case 'WORKER_APPLICATION_STATUS':
        return 'team';

      default:
        return 'general';
    }
  }

  /// Notification primary icon
  IconData get icon {
    switch (type) {
      case 'REPORT_ACKNOWLEDGED':
        return Icons.verified_user_rounded;
      case 'WORKER_ASSIGNED':
        return Icons.engineering_rounded;
      case 'WORKER_PROGRESS_NOTE':
        return Icons.edit_note_rounded;
      case 'REPORT_RESOLVED':
        return Icons.check_circle_rounded;
      case 'REPORT_REJECTED':
        return Icons.cancel_rounded;
      case 'NEW_REPORT':
        return Icons.campaign_rounded;

      case 'WORK_ASSIGNED':
        return Icons.assignment_late_rounded;
      case 'ADMIN_PROGRESS_REQUEST':
        return Icons.notification_important_rounded;

      case 'LF_MATCH':
        return Icons.auto_awesome_rounded;
      case 'LF_CLAIM_RECEIVED':
        return Icons.contact_page_rounded;
      case 'LF_HANDOVER_INTENT':
        return Icons.handshake_rounded;
      case 'LF_HANDOVER_COMPLETED':
        return Icons.task_alt_rounded;

      case 'COMMUNITY_ANNOUNCEMENT':
        return Icons.announcement_rounded;
      case 'COMMUNITY_POST':
      case 'NEW_COMMUNITY_POST':
        return Icons.forum_rounded;

      case 'WORKER_LEAVE':
        return Icons.event_busy_rounded;
      case 'WORKER_RESIGNED':
        return Icons.person_off_rounded;
      case 'NEW_WORKER_APPLICATION':
        return Icons.badge_rounded;
      case 'WORKER_APPLICATION_STATUS':
        return Icons.approval_rounded;

      default:
        return Icons.notifications_rounded;
    }
  }

  /// Themed accent color for badges and glowing effects
  Color get accentColor {
    switch (type) {
      case 'REPORT_ACKNOWLEDGED':
        return const Color(0xFF00B0FF); // Electric Cyan
      case 'WORKER_ASSIGNED':
        return const Color(0xFF7C4DFF); // Deep Purple
      case 'WORKER_PROGRESS_NOTE':
        return const Color(0xFFFF9100); // Amber
      case 'REPORT_RESOLVED':
        return const Color(0xFF00E676); // Emerald Green
      case 'REPORT_REJECTED':
        return const Color(0xFFFF5252); // Coral Red
      case 'NEW_REPORT':
        return const Color(0xFFFF3D00); // Bright Orange/Red

      case 'WORK_ASSIGNED':
        return const Color(0xFFFF6D00); // Vivid Orange
      case 'ADMIN_PROGRESS_REQUEST':
        return const Color(0xFFFF1744); // Urgent Pink/Red

      case 'LF_MATCH':
        return const Color(0xFF00E5FF); // Neon Aqua
      case 'LF_CLAIM_RECEIVED':
        return const Color(0xFFFFD600); // Gold
      case 'LF_HANDOVER_INTENT':
        return const Color(0xFF00E676); // Emerald
      case 'LF_HANDOVER_COMPLETED':
        return const Color(0xFF00C853); // Forest Emerald

      case 'COMMUNITY_ANNOUNCEMENT':
        return const Color(0xFFFF4081); // Bright Magenta
      case 'COMMUNITY_POST':
      case 'NEW_COMMUNITY_POST':
        return const Color(0xFF651FFF); // Indigo

      case 'WORKER_LEAVE':
        return const Color(0xFFFFAB00); // Amber Warning
      case 'WORKER_RESIGNED':
        return const Color(0xFFFF1744); // Crimson
      case 'NEW_WORKER_APPLICATION':
        return const Color(0xFF00B0FF); // Sky Blue
      case 'WORKER_APPLICATION_STATUS':
        return const Color(0xFF00E676); // Mint Green

      default:
        return const Color(0xFF00B0FF);
    }
  }

  /// Friendly relative time formatting
  String get relativeTime {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inSeconds < 45) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }
}
