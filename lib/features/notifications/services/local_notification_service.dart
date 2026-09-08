import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/services/debug_logger.dart';

/// Singleton service managing on-device local notifications using [FlutterLocalNotificationsPlugin].
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Stream controller notifying listeners when a notification is clicked
  final StreamController<Map<String, dynamic>> _onNotificationClickController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNotificationClick =>
      _onNotificationClickController.stream;

  // Notification Channel Constants
  static const String civicChannelId = 'nivara_civic_alerts';
  static const String civicChannelName = 'Civic Updates';
  static const String civicChannelDesc =
      'Notifications for report acknowledgements, progress notes, and resolutions';

  static const String dispatchChannelId = 'nivara_field_dispatch';
  static const String dispatchChannelName = 'Task & Field Dispatch';
  static const String dispatchChannelDesc =
      'Urgent assignments, tasks, and administrative progress requests';

  static const String communityChannelId = 'nivara_community_broadcasts';
  static const String communityChannelName = 'Community & Lost and Found';
  static const String communityChannelDesc =
      'Lost & Found match alerts, claims, handovers, and community announcements';

  /// Initializes the local notification plugin and configures notification channels.
  Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _notificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payloadStr = response.payload;
        if (payloadStr != null && payloadStr.isNotEmpty) {
          try {
            final data = jsonDecode(payloadStr) as Map<String, dynamic>;
            _onNotificationClickController.add(data);
          } catch (e) {
            DebugLogger.instance.log('NOTIF', 'Failed to parse notification payload: $e');
          }
        }
      },
    );

    // Create Android notification channels
    if (!kIsWeb && Platform.isAndroid) {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            civicChannelId,
            civicChannelName,
            description: civicChannelDesc,
            importance: Importance.high,
            enableVibration: true,
            playSound: true,
          ),
        );

        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            dispatchChannelId,
            dispatchChannelName,
            description: dispatchChannelDesc,
            importance: Importance.max,
            enableVibration: true,
            playSound: true,
          ),
        );

        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            communityChannelId,
            communityChannelName,
            description: communityChannelDesc,
            importance: Importance.defaultImportance,
            enableVibration: true,
            playSound: true,
          ),
        );

        // Request POST_NOTIFICATIONS permission on Android 13+
        await androidPlugin.requestNotificationsPermission();
      }
    }

    _initialized = true;
    DebugLogger.instance.log('NOTIF', 'LocalNotificationService initialized successfully');
  }

  /// Displays an immediate local notification popup banner.
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final channelId = _channelIdForType(type);
      final channelName = _channelNameForType(type);
      final channelDesc = _channelDescForType(type);

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: _importanceForType(type),
        priority: _priorityForType(type),
        styleInformation: BigTextStyleInformation(body),
        icon: '@mipmap/ic_launcher',
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      final payloadJson = jsonEncode({
        'type': type,
        'payload': payload ?? {},
      });

      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payloadJson,
      );
    } catch (e) {
      DebugLogger.instance.log('NOTIF', 'Error showing notification: $e');
    }
  }

  String _channelIdForType(String type) {
    switch (type) {
      case 'WORK_ASSIGNED':
      case 'ADMIN_PROGRESS_REQUEST':
      case 'NEW_REPORT':
        return dispatchChannelId;
      case 'LF_MATCH':
      case 'LF_CLAIM_RECEIVED':
      case 'LF_HANDOVER_INTENT':
      case 'LF_HANDOVER_COMPLETED':
      case 'COMMUNITY_ANNOUNCEMENT':
      case 'COMMUNITY_POST':
      case 'NEW_COMMUNITY_POST':
        return communityChannelId;
      default:
        return civicChannelId;
    }
  }

  String _channelNameForType(String type) {
    switch (type) {
      case 'WORK_ASSIGNED':
      case 'ADMIN_PROGRESS_REQUEST':
      case 'NEW_REPORT':
        return dispatchChannelName;
      case 'LF_MATCH':
      case 'LF_CLAIM_RECEIVED':
      case 'LF_HANDOVER_INTENT':
      case 'LF_HANDOVER_COMPLETED':
      case 'COMMUNITY_ANNOUNCEMENT':
      case 'COMMUNITY_POST':
      case 'NEW_COMMUNITY_POST':
        return communityChannelName;
      default:
        return civicChannelName;
    }
  }

  String _channelDescForType(String type) {
    switch (type) {
      case 'WORK_ASSIGNED':
      case 'ADMIN_PROGRESS_REQUEST':
      case 'NEW_REPORT':
        return dispatchChannelDesc;
      case 'LF_MATCH':
      case 'LF_CLAIM_RECEIVED':
      case 'LF_HANDOVER_INTENT':
      case 'LF_HANDOVER_COMPLETED':
      case 'COMMUNITY_ANNOUNCEMENT':
      case 'COMMUNITY_POST':
      case 'NEW_COMMUNITY_POST':
        return communityChannelDesc;
      default:
        return civicChannelDesc;
    }
  }

  Importance _importanceForType(String type) {
    switch (type) {
      case 'WORK_ASSIGNED':
      case 'ADMIN_PROGRESS_REQUEST':
      case 'NEW_REPORT':
      case 'LF_MATCH':
        return Importance.max;
      case 'COMMUNITY_POST':
      case 'NEW_COMMUNITY_POST':
        return Importance.defaultImportance;
      default:
        return Importance.high;
    }
  }

  Priority _priorityForType(String type) {
    switch (type) {
      case 'WORK_ASSIGNED':
      case 'ADMIN_PROGRESS_REQUEST':
      case 'NEW_REPORT':
      case 'LF_MATCH':
        return Priority.max;
      case 'COMMUNITY_POST':
      case 'NEW_COMMUNITY_POST':
        return Priority.defaultPriority;
      default:
        return Priority.high;
    }
  }
}
