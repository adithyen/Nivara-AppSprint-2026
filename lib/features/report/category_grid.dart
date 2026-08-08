import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/enums.dart';

/// Material icon for each civic category. Kept in one place so the grid, report
/// tiles, and map pins can all share a consistent visual language.
IconData categoryIcon(ReportCategory c) => switch (c) {
      ReportCategory.pothole => Icons.dangerous,
      ReportCategory.brokenFootpath => Icons.directions_walk,
      ReportCategory.openManhole => Icons.circle_outlined,
      ReportCategory.fallenTree => Icons.park,
      ReportCategory.waterlogging => Icons.water,
      ReportCategory.roadSign => Icons.signpost,
      ReportCategory.garbage => Icons.delete,
      ReportCategory.blockedDrain => Icons.water_damage,
      ReportCategory.sewage => Icons.plumbing,
      ReportCategory.streetLight => Icons.lightbulb,
      ReportCategory.damagedPole => Icons.electrical_services,
      ReportCategory.powerIssue => Icons.power,
      ReportCategory.waterSupply => Icons.water_drop,
      ReportCategory.pipeLeak => Icons.plumbing,
      ReportCategory.encroachment => Icons.fence,
      ReportCategory.brokenProperty => Icons.broken_image,
      ReportCategory.strayAnimals => Icons.pets,
      ReportCategory.noise => Icons.volume_up,
      ReportCategory.other => Icons.more_horiz,
    };

/// A tappable 3-column grid of all 19 civic categories. [selected] is
/// highlighted; tapping one calls [onSelect].
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final ReportCategory? selected;
  final ValueChanged<ReportCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.95,
      children: [
        for (final c in ReportCategory.values)
          _CategoryTile(
            category: c,
            selected: c == selected,
            onTap: () => onSelect(c),
          ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final ReportCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? NivaraColors.primary.withValues(alpha: 0.12)
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? NivaraColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                categoryIcon(category),
                color: selected ? NivaraColors.primary : scheme.onSurfaceVariant,
                size: 26,
              ),
              const SizedBox(height: 6),
              Text(
                category.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected ? NivaraColors.primary : null,
                      fontWeight: selected ? FontWeight.w600 : null,
                      height: 1.1,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
