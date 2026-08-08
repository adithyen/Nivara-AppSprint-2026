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

  group('Report.toInsertMap', () {
    test('manual report writes wire enums and omits null fields', () {
      final r = Report(
        id: '',
        userId: 'u1',
        category: ReportCategory.garbage,
        severity: Severity.high,
        description: 'Overflowing bin at the corner',
        lat: 8.52,
        lng: 76.93,
        source: 'MANUAL',
        createdAt: DateTime(2026, 8, 8),
      );
      final m = r.toInsertMap();
      expect(m['user_id'], 'u1');
      expect(m['category'], 'GARBAGE');
      expect(m['severity'], 'HIGH');
      expect(m['source'], 'MANUAL');
      expect(m['description'], 'Overflowing bin at the corner');
      expect(m['lat'], 8.52);
      expect(m['lng'], 76.93);
      // Optional fields with no value are left out entirely.
      expect(m.containsKey('title'), isFalse);
      expect(m.containsKey('address'), isFalse);
      expect(m.containsKey('photo_urls'), isFalse);
      expect(m.containsKey('evidence_hash'), isFalse);
    });

    test('includes title, address and photo urls when present', () {
      final r = Report(
        id: '',
        userId: 'u1',
        category: ReportCategory.pothole,
        lat: 8.0,
        lng: 76.0,
        title: 'Deep pothole',
        address: 'MG Road',
        photoUrls: const ['https://x/y.jpg'],
        createdAt: DateTime(2026, 8, 8),
      );
      final m = r.toInsertMap();
      expect(m['title'], 'Deep pothole');
      expect(m['address'], 'MG Road');
      expect(m['photo_urls'], const ['https://x/y.jpg']);
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
