// Unit tests for the Lost & Found model layer — locks down the DB<->Dart
// mapping for lf_items without booting the app.

import 'package:flutter_test/flutter_test.dart';

import 'package:nivara/models/enums.dart';
import 'package:nivara/models/lf_item.dart';

void main() {
  group('LFCategory / LFItemType wire mapping', () {
    test('round-trips every LFCategory wire value', () {
      for (final c in LFCategory.values) {
        expect(LFCategory.fromWire(c.wire), c);
      }
    });

    test('LFCategory falls back to OTHER for unknown/null', () {
      expect(LFCategory.fromWire('NOPE'), LFCategory.other);
      expect(LFCategory.fromWire(null), LFCategory.other);
    });

    test('LFItemType round-trips and defaults to LOST', () {
      expect(LFItemType.fromWire('LOST'), LFItemType.lost);
      expect(LFItemType.fromWire('FOUND'), LFItemType.found);
      expect(LFItemType.fromWire(null), LFItemType.lost);
    });
  });

  group('LFItem.fromMap', () {
    test('parses a server row and derives isLost/isFound', () {
      final item = LFItem.fromMap({
        'id': 'l1',
        'user_id': 'u1',
        'item_type': 'FOUND',
        'category': 'WALLET',
        'title': 'Brown wallet',
        'description': 'Found near the bus stand',
        'lat': 8.52,
        'lng': 76.93,
        'event_date': '2026-08-05',
        'contact_method': 'PHONE',
        'contact_phone': '99999',
        'reward_amount': 200,
        'status': 'ACTIVE',
      });
      expect(item.itemType, LFItemType.found);
      expect(item.isFound, isTrue);
      expect(item.isLost, isFalse);
      expect(item.category, LFCategory.wallet);
      expect(item.eventDate.year, 2026);
      expect(item.eventDate.month, 8);
      expect(item.eventDate.day, 5);
      expect(item.rewardAmount, 200);
      // Legacy contact_phone rows still parse into contactValue.
      expect(item.contactValue, '99999');
    });
  });

  group('LFItem.toInsertMap', () {
    test('writes wire enums, ISO date, and omits null optionals', () {
      final item = LFItem(
        id: '',
        userId: 'u1',
        itemType: LFItemType.lost,
        category: LFCategory.keys,
        title: 'House keys',
        description: 'Bunch of 3 keys on a red ring',
        lat: 8.5,
        lng: 76.9,
        eventDate: DateTime(2026, 8, 7),
      );
      final m = item.toInsertMap();
      expect(m['user_id'], 'u1');
      expect(m['item_type'], 'LOST');
      expect(m['category'], 'KEYS');
      expect(m['title'], 'House keys');
      expect(m['event_date'], '2026-08-07'); // DATE column, no time part
      expect(m['contact_method'], 'PHONE'); // default method
      // Null optionals are left out entirely.
      expect(m.containsKey('photo_urls'), isFalse);
      expect(m.containsKey('location_label'), isFalse);
      expect(m.containsKey('contact_value'), isFalse);
      expect(m.containsKey('reward_amount'), isFalse);
    });

    test('includes reward, contact, label and photos when present', () {
      final item = LFItem(
        id: '',
        userId: 'u1',
        itemType: LFItemType.lost,
        category: LFCategory.mobilePhone,
        title: 'Black phone',
        description: 'Cracked screen',
        lat: 8.5,
        lng: 76.9,
        locationLabel: 'MG Road',
        eventDate: DateTime(2026, 8, 7),
        contactMethod: 'PHONE',
        contactValue: '12345',
        rewardAmount: 500,
        photoUrls: const ['https://x/y.jpg'],
      );
      final m = item.toInsertMap();
      expect(m['location_label'], 'MG Road');
      expect(m['contact_method'], 'PHONE');
      expect(m['contact_value'], '12345');
      expect(m['reward_amount'], 500);
      expect(m['photo_urls'], const ['https://x/y.jpg']);
      expect(m['is_private'], isFalse);
    });

    test('serializes is_private true when confidential mode is selected', () {
      final item = LFItem(
        id: '',
        userId: 'u1',
        itemType: LFItemType.lost,
        category: LFCategory.jewellery,
        title: 'Gold Ring',
        description: '24k gold band with engraved initials',
        lat: 8.5,
        lng: 76.9,
        eventDate: DateTime(2026, 8, 7),
        isPrivate: true,
      );
      final m = item.toInsertMap();
      expect(m['is_private'], isTrue);
    });
  });
}
