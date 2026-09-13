import 'package:flutter_test/flutter_test.dart';
import 'package:nivara/core/services/app_update_service.dart';

void main() {
  group('AppUpdateService.compareSemVer', () {
    test('identical versions return 0', () {
      expect(AppUpdateService.compareSemVer('1.0.64', '1.0.64'), 0);
      expect(AppUpdateService.compareSemVer('v1.0.64', '1.0.64'), 0);
      expect(AppUpdateService.compareSemVer('1.0.64+64', '1.0.64+64'), 0);
    });

    test('newer major returns negative when comparing current to remote', () {
      expect(AppUpdateService.compareSemVer('1.0.64', '2.0.0'), lessThan(0));
    });

    test('newer minor returns negative when comparing current to remote', () {
      expect(AppUpdateService.compareSemVer('1.0.64', '1.1.0'), lessThan(0));
    });

    test('newer patch returns negative when comparing current to remote', () {
      expect(AppUpdateService.compareSemVer('1.0.64', '1.0.65'), lessThan(0));
      expect(AppUpdateService.compareSemVer('1.0.64', 'v1.0.65'), lessThan(0));
    });

    test('older remote returns positive', () {
      expect(AppUpdateService.compareSemVer('1.0.64', '1.0.63'), greaterThan(0));
      expect(AppUpdateService.compareSemVer('1.0.64', 'v1.0.60'), greaterThan(0));
    });

    test('handles double digit versions properly', () {
      expect(AppUpdateService.compareSemVer('1.0.9', '1.0.10'), lessThan(0));
      expect(AppUpdateService.compareSemVer('1.0.100', '1.0.99'), greaterThan(0));
    });

    test('handles build number increments when version matches', () {
      expect(AppUpdateService.compareSemVer('1.0.64+64', '1.0.64+65'), lessThan(0));
    });
  });
}
