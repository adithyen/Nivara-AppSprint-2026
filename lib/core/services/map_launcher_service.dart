import 'package:url_launcher/url_launcher.dart';

/// Service for launching native navigation and 360° Google Maps Street View.
abstract final class MapLauncherService {
  /// Opens turn-by-turn driving navigation in Google Maps / native maps app.
  static Future<bool> launchNavigation(double lat, double lng) async {
    final nativeUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    try {
      if (await canLaunchUrl(nativeUri)) {
        return await launchUrl(nativeUri);
      }
      return await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        return await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }

  /// Opens Google Maps 360° Street View panorama at the exact GPS coordinates.
  static Future<bool> launchStreetView(double lat, double lng) async {
    final nativeUri = Uri.parse('google.streetview:cbll=$lat,$lng');
    final webUri = Uri.parse(
      'https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=$lat,$lng',
    );
    try {
      if (await canLaunchUrl(nativeUri)) {
        return await launchUrl(nativeUri);
      }
      return await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        return await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }
}
