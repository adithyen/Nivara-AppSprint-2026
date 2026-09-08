import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets/bouncy_tap.dart';
import '../../../core/widgets/staggered_entrance.dart';
import '../../../models/enums.dart';
import '../../../models/lf_item.dart';
import '../../../models/report.dart';
import '../../../router.dart';
import '../../auth/auth_controller.dart';
import '../../settings/accessibility_controller.dart';
import '../../settings/language_controller.dart';
import '../data/notification_model.dart';
import '../data/notification_repository.dart';

/// 2026-Level Flagship Notification Center with Realtime synchronization,
/// deep-linking, category filtering, and tactile micro-interactions.
class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  String _selectedFilter = 'all'; // 'all', 'unread', 'reports', 'work', 'lostfound', 'community', 'team'

  @override
  Widget build(BuildContext context) {
    final currentLang = ref.watch(languageControllerProvider);
    final a11y = ref.watch(accessibilityControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final notificationsAsync = ref.watch(notificationsStreamProvider);
    final user = ref.watch(authControllerProvider).asData?.value;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark
            ? const Color(0xFF0C1117).withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.90),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BouncyTap(
          onTap: () => context.pop(),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              color: isDark ? Colors.white : Colors.black87,
              size: 20,
            ),
          ),
        ),
        title: Text(
          NivaraStrings.tr('notifications_title', currentLang),
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF101828),
            fontWeight: FontWeight.w800,
            fontSize: 19,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          notificationsAsync.maybeWhen(
            data: (list) {
              final hasUnread = list.any((n) => !n.isRead);
              if (list.isEmpty) return const SizedBox.shrink();

              return Row(
                children: [
                  if (hasUnread)
                    IconButton(
                      tooltip: NivaraStrings.tr('notifications_mark_all_read', currentLang),
                      icon: Icon(
                        Icons.done_all_rounded,
                        color: primary,
                        size: 22,
                      ),
                      onPressed: () async {
                        if (user != null) {
                          if (a11y.hapticsEnabled) {
                            HapticFeedback.lightImpact();
                          }
                          await ref
                              .read(notificationRepositoryProvider)
                              .markAllAsRead(user.id);
                        }
                      },
                    ),
                  IconButton(
                    tooltip: NivaraStrings.tr('notifications_clear_all', currentLang),
                    icon: Icon(
                      Icons.delete_sweep_rounded,
                      color: isDark ? Colors.white60 : Colors.black54,
                      size: 22,
                    ),
                    onPressed: () => _confirmClearAll(context, user?.id),
                  ),
                  const SizedBox(width: 8),
                ],
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  'Error loading alerts: $error',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
        data: (notifications) {
          final filtered = _filterNotifications(notifications);

          return Column(
            children: [
              _buildFilterChips(notifications, currentLang, isDark, primary),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState(currentLang, isDark, primary)
                    : RefreshIndicator(
                        onRefresh: () async {
                          if (user != null) {
                            await ref
                                .read(notificationRepositoryProvider)
                                .fetchNotifications(user.id);
                          }
                        },
                        color: primary,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final notif = filtered[index];
                            return StaggeredEntrance(
                              index: index.clamp(0, 10),
                              child: _NotificationCard(
                                notification: notif,
                                isDark: isDark,
                                onDismiss: () async {
                                  if (a11y.hapticsEnabled) {
                                    HapticFeedback.mediumImpact();
                                  }
                                  await ref
                                      .read(notificationRepositoryProvider)
                                      .deleteNotification(notif.id);
                                },
                                onTap: () => _handleNotificationTap(context, notif),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<AppNotification> _filterNotifications(List<AppNotification> list) {
    switch (_selectedFilter) {
      case 'unread':
        return list.where((n) => !n.isRead).toList();
      case 'reports':
        return list.where((n) => n.category == 'reports').toList();
      case 'work':
        return list.where((n) => n.category == 'work').toList();
      case 'lostfound':
        return list.where((n) => n.category == 'lostfound').toList();
      case 'community':
        return list.where((n) => n.category == 'community').toList();
      case 'team':
        return list.where((n) => n.category == 'team').toList();
      default:
        return list;
    }
  }

  Widget _buildFilterChips(
    List<AppNotification> all,
    AppLanguage lang,
    bool isDark,
    Color primary,
  ) {
    final unreadCount = all.where((n) => !n.isRead).length;
    final reportsCount = all.where((n) => n.category == 'reports').length;
    final workCount = all.where((n) => n.category == 'work').length;
    final lfCount = all.where((n) => n.category == 'lostfound').length;
    final commCount = all.where((n) => n.category == 'community').length;

    final chips = [
      ('all', NivaraStrings.tr('notifications_filter_all', lang), all.length),
      ('unread', NivaraStrings.tr('notifications_filter_unread', lang), unreadCount),
      ('reports', NivaraStrings.tr('notifications_filter_reports', lang), reportsCount),
      ('work', NivaraStrings.tr('notifications_filter_work', lang), workCount),
      ('lostfound', NivaraStrings.tr('notifications_filter_lostfound', lang), lfCount),
      ('community', NivaraStrings.tr('notifications_filter_community', lang), commCount),
    ];

    return Container(
      height: 48,
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = chips[index];
          final isSelected = _selectedFilter == item.$1;

          return BouncyTap(
            onTap: () {
              setState(() => _selectedFilter = item.$1);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? primary
                    : (isDark
                        ? const Color(0xFF161F2C)
                        : const Color(0xFFF1F4F9)),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? primary
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06)),
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.$2,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.white70 : Colors.black87),
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (item.$3 > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.25)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.08)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${item.$3}',
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white60 : Colors.black54),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(AppLanguage lang, bool isDark, Color primary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primary.withValues(alpha: isDark ? 0.25 : 0.15),
                    Colors.transparent,
                  ],
                ),
                border: Border.all(
                  color: primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.notifications_none_rounded,
                  size: 38,
                  color: primary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              NivaraStrings.tr('notifications_empty', lang),
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF101828),
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You are completely caught up! We will notify you whenever civic updates, task dispatches, or community alerts occur.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleNotificationTap(
    BuildContext context,
    AppNotification notif,
  ) async {
    // 1. Mark as read immediately
    if (!notif.isRead) {
      await ref.read(notificationRepositoryProvider).markAsRead(notif.id);
    }

    final payload = notif.payload;
    final userProfile = ref.read(authControllerProvider).asData?.value;
    final role = userProfile?.role ?? UserRole.citizen;

    // 2. Handle Civic Report Routing
    if (payload.containsKey('report_id')) {
      final reportId = payload['report_id'] as String;

      // Show temporary indicator while resolving report
      try {
        final row = await supabase
            .from(kTableReports)
            .select()
            .eq('id', reportId)
            .maybeSingle();

        if (row != null && context.mounted) {
          final report = Report.fromMap(row);

          if (role == UserRole.admin) {
            context.push(Routes.adminReportDetail, extra: report);
          } else if (role == UserRole.worker && report.assignedTo == userProfile?.id) {
            context.push(Routes.workerTask, extra: report);
          } else {
            context.push(Routes.reportDetail, extra: report);
          }
          return;
        }
      } catch (_) {}
    }

    // 3. Handle Lost & Found Item or Match Routing
    if (payload.containsKey('item_id')) {
      final itemId = payload['item_id'] as String;
      try {
        final row = await supabase
            .from(kTableLfItems)
            .select()
            .eq('id', itemId)
            .maybeSingle();

        if (row != null && context.mounted) {
          final item = LFItem.fromMap(row);
          if (notif.type == 'LF_MATCH') {
            context.push(Routes.lostFoundMatch, extra: item);
          } else {
            context.push(Routes.lostFoundDetail, extra: item);
          }
          return;
        }
      } catch (_) {}
    }

    // 4. Handle Claim / Handover Routing
    if (payload.containsKey('claim_id')) {
      if (context.mounted) {
        context.push(Routes.myListings);
        return;
      }
    }

    // 5. Handle Community Post Routing
    if (payload.containsKey('post_id')) {
      if (context.mounted) {
        if (role == UserRole.admin) {
          context.push(Routes.admin);
        } else {
          context.push(Routes.home);
        }
        return;
      }
    }

    // 6. Handle Staff / Application Routing
    if (notif.type == 'NEW_WORKER_APPLICATION' || notif.type == 'WORKER_LEAVE') {
      if (role == UserRole.admin && context.mounted) {
        context.push(Routes.admin);
        return;
      }
    }
  }

  Future<void> _confirmClearAll(BuildContext context, String? uid) async {
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text(
          'This will permanently remove all notifications from your alert history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF1744),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(notificationRepositoryProvider).clearAll(uid);
    }
  }
}

/// 2026-Level Glassmorphic Notification Card with swipe-to-dismiss & live visual styling.
class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final bool isDark;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.isDark,
    required this.onDismiss,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = notification.accentColor;
    final isUnread = !notification.isRead;

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFF1744),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.white,
          size: 26,
        ),
      ),
      child: BouncyTap(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? (isUnread
                    ? const Color(0xFF141C27)
                    : const Color(0xFF0F151E))
                : (isUnread
                    ? Colors.white
                    : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isUnread
                  ? accent.withValues(alpha: isDark ? 0.45 : 0.5)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06)),
              width: isUnread ? 1.5 : 1.0,
            ),
            boxShadow: [
              if (isUnread)
                BoxShadow(
                  color: accent.withValues(alpha: isDark ? 0.2 : 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon Squircle
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accent.withValues(alpha: isDark ? 0.28 : 0.18),
                            accent.withValues(alpha: isDark ? 0.12 : 0.08),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          notification.icon,
                          color: accent,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Text Body & Time
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  notification.title,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF101828),
                                    fontSize: 14.5,
                                    fontWeight: isUnread
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Row(
                                children: [
                                  Text(
                                    notification.relativeTime,
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.black45,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (isUnread) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: accent,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: accent.withValues(alpha: 0.6),
                                            blurRadius: 4,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            notification.body,
                            style: TextStyle(
                              color: isDark
                                  ? (isUnread ? Colors.white70 : Colors.white60)
                                  : (isUnread
                                      ? const Color(0xFF334155)
                                      : const Color(0xFF64748B)),
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
