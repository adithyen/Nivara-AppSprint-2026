import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/enums.dart';
import '../../models/lf_item.dart';

/// Material icon for each Lost & Found category — shared by the form's category
/// picker, the item cards, and the match list so the visual language matches.
IconData lfCategoryIcon(LFCategory c) => switch (c) {
  LFCategory.aadhaar => Icons.badge,
  LFCategory.panCard => Icons.credit_card,
  LFCategory.drivingLicence => Icons.directions_car_filled,
  LFCategory.passport => Icons.menu_book,
  LFCategory.otherDocument => Icons.description,
  LFCategory.mobilePhone => Icons.smartphone,
  LFCategory.wallet => Icons.account_balance_wallet,
  LFCategory.keys => Icons.vpn_key,
  LFCategory.bag => Icons.work,
  LFCategory.jewellery => Icons.diamond,
  LFCategory.pet => Icons.pets,
  LFCategory.vehicle => Icons.two_wheeler,
  LFCategory.other => Icons.category,
};

/// A compact card for one lost/found entry. Colour-cued by [LFItem.itemType]
/// (lost = danger red, found = success green). Optional [distanceMeters] shows
/// how far the item is from a reference point (used in the match list).
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
    final scheme = Theme.of(context).colorScheme;
    final isLost = item.isLost;
    final accent = isLost ? NivaraColors.danger : NivaraColors.success;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: accent.withValues(alpha: 0.15),
                child: Icon(lfCategoryIcon(item.category), color: accent),
              ),
              const SizedBox(width: 12),
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
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        _TypeBadge(isLost: isLost, accent: accent),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 2,
                      children: [
                        _MetaLine(
                          icon: Icons.category_outlined,
                          text: item.category.label,
                        ),
                        _MetaLine(
                          icon: Icons.event_outlined,
                          text: formatDate(item.eventDate),
                        ),
                        if (item.locationLabel != null &&
                            item.locationLabel!.isNotEmpty)
                          _MetaLine(
                            icon: Icons.place_outlined,
                            text: item.locationLabel!,
                          ),
                        if (distanceMeters != null)
                          _MetaLine(
                            icon: Icons.near_me_outlined,
                            text: formatDistance(distanceMeters!),
                            color: NivaraColors.primary,
                          ),
                        if (item.rewardAmount != null && item.rewardAmount! > 0)
                          _MetaLine(
                            icon: Icons.card_giftcard,
                            text: '₹${item.rewardAmount}',
                            color: NivaraColors.accent,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (item.photoUrls != null && item.photoUrls!.isNotEmpty) ...[
                const SizedBox(width: 10),
                _Thumb(url: item.photoUrls!.first),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        loadingBuilder: (c, child, progress) => progress == null
            ? child
            : Container(
                width: 56,
                height: 56,
                color: scheme.surfaceContainerHighest,
              ),
        errorBuilder: (c, _, _) => Container(
          width: 56,
          height: 56,
          color: scheme.surfaceContainerHighest,
          child: Icon(Icons.image_outlined, size: 20, color: scheme.outline),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isLost ? 'LOST' : 'FOUND',
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w700,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 3),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: c,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
