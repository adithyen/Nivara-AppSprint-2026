import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../models/enums.dart';
import '../../models/lf_item.dart';

IconData lfCategoryIcon(LFCategory c) => switch (c) {
  LFCategory.aadhaar => Icons.badge_rounded,
  LFCategory.panCard => Icons.credit_card_rounded,
  LFCategory.drivingLicence => Icons.directions_car_filled_rounded,
  LFCategory.passport => Icons.menu_book_rounded,
  LFCategory.otherDocument => Icons.description_rounded,
  LFCategory.mobilePhone => Icons.smartphone_rounded,
  LFCategory.wallet => Icons.account_balance_wallet_rounded,
  LFCategory.keys => Icons.vpn_key_rounded,
  LFCategory.bag => Icons.work_rounded,
  LFCategory.jewellery => Icons.diamond_rounded,
  LFCategory.pet => Icons.pets_rounded,
  LFCategory.vehicle => Icons.two_wheeler_rounded,
  LFCategory.other => Icons.category_rounded,
};

/// 2026-Level Flagship Lost & Found Item Card.
class LFItemCard extends StatelessWidget {
  const LFItemCard({
    super.key,
    required this.item,
    this.distanceMeters,
    this.onTap,
  });

  final LFItem item;
  final double? distanceMeters;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final isLost = item.isLost;
    final accent = isLost ? NivaraColors.danger : primary;

    return BouncyTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF10161E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accent.withValues(alpha: isDark ? 0.3 : 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.16 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(lfCategoryIcon(item.category), color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF111827),
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                      _TypeBadge(isLost: isLost, accent: accent),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF6B7280),
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _MetaLine(
                        icon: Icons.category_outlined,
                        text: item.category.label,
                        isDark: isDark,
                      ),
                      _MetaLine(
                        icon: Icons.event_outlined,
                        text: formatDate(item.eventDate),
                        isDark: isDark,
                      ),
                      if (item.locationLabel != null &&
                          item.locationLabel!.isNotEmpty)
                        _MetaLine(
                          icon: Icons.place_outlined,
                          text: item.locationLabel!,
                          isDark: isDark,
                        ),
                      if (distanceMeters != null)
                        _MetaLine(
                          icon: Icons.near_me_rounded,
                          text: formatDistance(distanceMeters!),
                          color: primary,
                          isDark: isDark,
                        ),
                      if (item.rewardAmount != null && item.rewardAmount! > 0)
                        _MetaLine(
                          icon: Icons.card_giftcard_rounded,
                          text: '₹${item.rewardAmount}',
                          color: NivaraColors.accent,
                          isDark: isDark,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isLost ? const Color(0xFF00E676) : const Color(0xFF00B0FF))
                          .withValues(alpha: isDark ? 0.12 : 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (isLost ? const Color(0xFF00E676) : const Color(0xFF00B0FF))
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isLost ? Icons.volunteer_activism_rounded : Icons.verified_rounded,
                          size: 12,
                          color: isLost ? const Color(0xFF00E676) : const Color(0xFF00B0FF),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isLost ? 'Direct Handover' : 'Direct Claim',
                          style: TextStyle(
                            color: isLost ? const Color(0xFF00E676) : const Color(0xFF00B0FF),
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (item.photoUrls != null && item.photoUrls!.isNotEmpty) ...[
              const SizedBox(width: 10),
              _Thumb(url: item.photoUrls!.first, isDark: isDark),
            ],
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.isDark});
  final String url;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: 54,
          height: 54,
          color: isDark ? const Color(0xFF131A24) : const Color(0xFFF1F5F9),
          child: Icon(
            Icons.image_outlined,
            size: 20,
            color: isDark ? Colors.white38 : Colors.black26,
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.isLost, required this.accent});
  final bool isLost;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Text(
        isLost ? 'LOST' : 'FOUND',
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
          fontSize: 10.5,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.icon,
    required this.text,
    this.color,
    required this.isDark,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final c = color ?? (isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF6B7280));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: c,
            fontWeight: FontWeight.w600,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}
