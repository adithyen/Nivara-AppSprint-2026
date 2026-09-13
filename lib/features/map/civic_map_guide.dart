import 'package:flutter/material.dart';
import '../../core/widgets/interactive_info_guide_sheet.dart';

/// Renders a high-fidelity visual sample of an Ola Map marker pin badge.
class SampleMapPinBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const SampleMapPinBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.7 : 0.5),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.25 : 0.12),
            blurRadius: 6,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6.5,
            height: 6.5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.8),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          if (icon != null) ...[
            const SizedBox(width: 4),
            Icon(icon, size: 10, color: color),
          ],
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual status progression matrix displaying sample pin styles and transitions.
class CivicMapVisualMatrix extends StatelessWidget {
  const CivicMapVisualMatrix({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryText = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131A24) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_rounded, size: 16, color: Color(0xFF00E676)),
              const SizedBox(width: 8),
              Text(
                'LIVE STATUS PIN CODING',
                style: TextStyle(
                  color: primaryText,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Hazard pins dynamically change color on the Ola Vector Map as municipal action progresses:',
            style: TextStyle(
              color: secondaryText,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          // 4-Stage Pin Progression Bar
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              SampleMapPinBadge(label: 'SUBMITTED', color: Color(0xFFFF3B30)),
              SampleMapPinBadge(label: 'ACKNOWLEDGED', color: Color(0xFFFF9500)),
              SampleMapPinBadge(label: 'ASSIGNED', color: Color(0xFFFFD600)),
              SampleMapPinBadge(label: 'IN PROGRESS', color: Color(0xFF00E676)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Helper to trigger the Civic Map guide bottom sheet.
void showCivicMapGuide(BuildContext context) {
  InteractiveInfoGuideSheet.show(
    context,
    preferenceKey: 'has_acknowledged_map_guide',
    icon: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E676).withValues(alpha: 0.35),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Icon(Icons.explore_rounded, size: 36, color: Colors.black),
    ),
    title: 'Civic Map Intelligence & Pins',
    subtitle: 'Pin Color Coding, Category Indicators & Hyperlocal Radar',
    actionLabel: 'Explore Live Map',
    customHeader: const CivicMapVisualMatrix(),
    items: const [
      GuideInfoCardItem(
        icon: Icons.new_releases_rounded,
        iconColor: Color(0xFFFF3B30),
        title: 'Red Pin · Submitted / In Review',
        description:
            'A freshly logged road or civic hazard awaiting municipal officer triage and priority evaluation.',
        trailingBadge: SampleMapPinBadge(
          label: 'SUBMITTED',
          color: Color(0xFFFF3B30),
        ),
      ),
      GuideInfoCardItem(
        icon: Icons.assignment_late_rounded,
        iconColor: Color(0xFFFF9500),
        title: 'Orange Pin · Acknowledged by City',
        description:
            'Verified by administrative command. Responsible department identified; pending field staff dispatch.',
        trailingBadge: SampleMapPinBadge(
          label: 'ACKNOWLEDGED',
          color: Color(0xFFFF9500),
        ),
      ),
      GuideInfoCardItem(
        icon: Icons.engineering_rounded,
        iconColor: Color(0xFFFFD600),
        title: 'Yellow Pin · Field Crew Assigned',
        description:
            'Assigned to certified municipal field crew in this ward. Team scheduled for on-site remediation inspection.',
        trailingBadge: SampleMapPinBadge(
          label: 'ASSIGNED',
          color: Color(0xFFFFD600),
        ),
      ),
      GuideInfoCardItem(
        icon: Icons.build_circle_rounded,
        iconColor: Color(0xFF00E676),
        title: 'Green Pin · Work in Progress',
        description:
            'Repair operations actively underway on site; pending after-fix photo proof and citizen community confirmation.',
        trailingBadge: SampleMapPinBadge(
          label: 'IN PROGRESS',
          color: Color(0xFF00E676),
        ),
      ),
      GuideInfoCardItem(
        icon: Icons.radar_rounded,
        iconColor: Color(0xFFFF6D00),
        title: 'Lost & Found Beacons',
        description:
            '🔴 Orange beacons denote lost items seeking discovery; 🔵 Cyan beacons show found valuables in secure custody.',
        trailingBadge: SampleMapPinBadge(
          label: 'L&F RADAR',
          color: Color(0xFFFF6D00),
        ),
      ),
      GuideInfoCardItem(
        icon: Icons.local_hospital_rounded,
        iconColor: Color(0xFF448AFF),
        title: 'Emergency Services Discovery',
        description:
            'Tap the top chips to locate nearby Hospitals (🏥), Police Kiosks (👮), Metro & Transit (🚌), and Fire Stations (🚒).',
        trailingBadge: SampleMapPinBadge(
          label: 'POIs',
          color: Color(0xFF448AFF),
        ),
      ),
    ],
  );
}
