// Unit tests for Nivara's pure model/util layer. These avoid booting the app
// (which needs Supabase init) and instead lock down the DB<->Dart mapping.

import 'package:flutter_test/flutter_test.dart';

import 'package:nivara/core/utils.dart';
import 'package:nivara/models/enums.dart';
import 'package:nivara/models/report.dart';

void main() {
  group('enum wire mapping', () {
    test('round-trips every ReportCategory wire value', () {
      for (final c in ReportCategory.values) {
        expect(ReportCategory.fromWire(c.wire), c);
      }
    });

    test('falls back to OTHER for unknown category', () {
      expect(ReportCategory.fromWire('NOT_A_REAL_ONE'), ReportCategory.other);
      expect(ReportCategory.fromWire(null), ReportCategory.other);
    });

    test('nullable department parses null and unknowns to null', () {
      expect(AdminDepartment.fromWire(null), isNull);
      expect(AdminDepartment.fromWire('BOGUS'), isNull);
      expect(AdminDepartment.fromWire('ROADS'), AdminDepartment.roads);
    });
  });

  group('Report.fromMap', () {
    test('parses a minimal server row', () {
      final r = Report.fromMap({
        'id': 'r1',
        'user_id': 'u1',
        'category': 'POTHOLE',
        'status': 'SUBMITTED',
        'severity': 'HIGH',
        'lat': 8.52,
        'lng': 76.93,
        'source': 'SENSORWATCH',
        'created_at': '2026-08-08T10:00:00Z',
      });
      expect(r.category, ReportCategory.pothole);
      expect(r.status, ReportStatus.submitted);
      expect(r.severity, Severity.high);
      expect(r.isFromSensor, isTrue);
      expect(r.lat, closeTo(8.52, 1e-9));
    });
  });

  group('haversineMeters', () {
    test('is ~0 for identical points', () {
      expect(haversineMeters(8.52, 76.93, 8.52, 76.93), closeTo(0, 1e-6));
    });

    test('matches a known ~1 degree latitude span (~111 km)', () {
      final d = haversineMeters(8.0, 76.0, 9.0, 76.0);
      expect(d, closeTo(111195, 500));
    });
  });
}
