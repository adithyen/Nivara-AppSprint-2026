import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../models/enums.dart';
import '../settings/language_controller.dart';

IconData categoryIcon(ReportCategory c) => switch (c) {
  ReportCategory.pothole => Icons.dangerous_rounded,
  ReportCategory.brokenFootpath => Icons.directions_walk_rounded,
  ReportCategory.openManhole => Icons.circle_outlined,
  ReportCategory.fallenTree => Icons.park_rounded,
  ReportCategory.waterlogging => Icons.water_rounded,
  ReportCategory.roadSign => Icons.signpost_rounded,
  ReportCategory.garbage => Icons.delete_rounded,
  ReportCategory.blockedDrain => Icons.water_damage_rounded,
  ReportCategory.sewage => Icons.plumbing_rounded,
  ReportCategory.streetLight => Icons.lightbulb_rounded,
  ReportCategory.damagedPole => Icons.electrical_services_rounded,
  ReportCategory.powerIssue => Icons.power_rounded,
  ReportCategory.waterSupply => Icons.water_drop_rounded,
  ReportCategory.pipeLeak => Icons.plumbing_rounded,
  ReportCategory.encroachment => Icons.fence_rounded,
  ReportCategory.brokenProperty => Icons.broken_image_rounded,
  ReportCategory.strayAnimals => Icons.pets_rounded,
  ReportCategory.noise => Icons.volume_up_rounded,
  ReportCategory.other => Icons.more_horiz_rounded,
};

/// 2026-Level Cyber-Civic Category Grid.
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({
    super.key,
    required this.selected,
    required this.onSelect,
    this.currentLang = AppLanguage.en,
  });

  final ReportCategory? selected;
  final ValueChanged<ReportCategory> onSelect;
  final AppLanguage currentLang;

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
            currentLang: currentLang,
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
    this.currentLang = AppLanguage.en,
  });

  final ReportCategory category;
  final bool selected;
  final VoidCallback onTap;
  final AppLanguage currentLang;

  @override
  Widget build(BuildContext context) {
    return BouncyTap(
      onTap: onTap,
      scaleFactor: 0.92,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected
              ? NivaraColors.primary.withValues(alpha: 0.16)
              : const Color(0xFF10161E),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? NivaraColors.primary
                : Colors.white.withValues(alpha: 0.08),
            width: selected ? 1.5 : 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: NivaraColors.primary.withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (selected ? NivaraColors.primary : Colors.white)
                    .withValues(alpha: selected ? 0.2 : 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                categoryIcon(category),
                color: selected ? NivaraColors.primary : Colors.white70,
                size: 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              category.localizedName(currentLang),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? NivaraColors.primary : Colors.white,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                fontSize: 11.5,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
