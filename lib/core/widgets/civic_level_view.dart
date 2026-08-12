import 'package:flutter/material.dart';

import '../civic_level.dart';

/// Compact level badge + progress bar for the civic-impact cards. Renders in
/// two skins: [onDark] for the gradient Home hero (white text/track) and the
/// default light skin for the Profile card (uses the level's own colour).
class CivicLevelBar extends StatelessWidget {
  const CivicLevelBar({super.key, required this.standing, this.onDark = false});

  final CivicStanding standing;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final level = standing.level;

    final textColor = onDark ? Colors.white : scheme.onSurface;
    final subColor = onDark
        ? Colors.white.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;
    final track = onDark
        ? Colors.white.withValues(alpha: 0.25)
        : scheme.surfaceContainerHighest;
    final fill = onDark ? Colors.white : level.color;
    final chipBg = onDark
        ? Colors.white.withValues(alpha: 0.18)
        : level.color.withValues(alpha: 0.15);
    final iconColor = onDark ? Colors.white : level.color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: chipBg, shape: BoxShape.circle),
              child: Icon(level.icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Level ${level.rank} · ${level.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    level.blurb,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: subColor, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: standing.progress,
            minHeight: 7,
            backgroundColor: track,
            valueColor: AlwaysStoppedAnimation<Color>(fill),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          level.isMax
              ? 'Top rank reached — you\'re a Nivara Legend.'
              : '${standing.pointsToNext} pts to Level ${level.rank + 1}',
          style: TextStyle(color: subColor, fontSize: 11.5),
        ),
      ],
    );
  }
}
