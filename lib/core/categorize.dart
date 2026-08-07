import '../models/enums.dart';

/// Maps a passive SensorWatch [DetectionType] to the civic [ReportCategory]
/// an auto-submitted report should carry. Manual reports pick their own
/// category, so this only covers the sensor-derived types.
ReportCategory categoryForDetection(DetectionType type) {
  switch (type) {
    case DetectionType.pothole:
      return ReportCategory.pothole;
    case DetectionType.speedBreaker:
      // Unmarked/harsh speed breakers are a roads issue; nearest civic bucket.
      return ReportCategory.pothole;
    case DetectionType.badRoad:
      return ReportCategory.brokenProperty;
    case DetectionType.manual:
      return ReportCategory.other;
  }
}

/// Default severity inferred from how hard the jolt was, in g above baseline.
Severity severityForImpact(double gAboveBaseline) {
  if (gAboveBaseline >= 5.0) return Severity.high;
  if (gAboveBaseline >= 3.5) return Severity.medium;
  return Severity.low;
}
