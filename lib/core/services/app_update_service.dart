import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

enum AppUpdateStatus {
  upToDate,
  updateAvailable,
  error,
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.status,
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    this.releaseTitle,
    this.releaseNotes,
    this.publishedAt,
    this.apkUrl,
    this.apkSizeBytes,
    this.apkFileName,
    this.errorMessage,
  });

  final AppUpdateStatus status;
  final String currentVersion;
  final String currentBuild;
  final String latestVersion;
  final String? releaseTitle;
  final String? releaseNotes;
  final DateTime? publishedAt;
  final String? apkUrl;
  final int? apkSizeBytes;
  final String? apkFileName;
  final String? errorMessage;

  bool get isUpdateAvailable => status == AppUpdateStatus.updateAvailable;
  bool get isUpToDate => status == AppUpdateStatus.upToDate;

  String get formattedSize {
    if (apkSizeBytes == null || apkSizeBytes! <= 0) return 'Unknown size';
    final mb = apkSizeBytes! / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class DownloadProgress {
  const DownloadProgress({
    required this.bytesReceived,
    required this.totalBytes,
    required this.percent,
    this.isDone = false,
    this.filePath,
    this.error,
  });

  final int bytesReceived;
  final int totalBytes;
  final double percent; // 0.0 to 1.0
  final bool isDone;
  final String? filePath;
  final String? error;

  String get formattedReceived {
    final mb = bytesReceived / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  String get formattedTotal {
    if (totalBytes <= 0) return '...';
    final mb = totalBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const String repoOwner = 'adithyen';
  static const String repoName = 'Nivara-AppSprint-2026';
  static const String releasesApiUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';
  static const String releasesWebUrl =
      'https://github.com/$repoOwner/$repoName/releases/latest';

  static const MethodChannel _channel = MethodChannel('in.adithyen.nivara/updater');

  /// Compares two SemVer strings (e.g. "1.0.64+64" vs "1.0.65+65" or "v1.0.65").
  /// Returns:
  /// - negative if v1 < v2 (v2 is newer)
  /// - 0 if v1 == v2
  /// - positive if v1 > v2 (v1 is newer)
  static int compareSemVer(String v1, String v2) {
    final clean1 = v1.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final clean2 = v2.trim().replaceFirst(RegExp(r'^[vV]'), '');

    // Split version and optional build numbers (+64)
    final parts1 = clean1.split('+');
    final parts2 = clean2.split('+');

    final semver1 = parts1[0].split('.');
    final semver2 = parts2[0].split('.');

    final maxLen = semver1.length > semver2.length ? semver1.length : semver2.length;
    for (var i = 0; i < maxLen; i++) {
      final num1 = i < semver1.length ? (int.tryParse(semver1[i]) ?? 0) : 0;
      final num2 = i < semver2.length ? (int.tryParse(semver2[i]) ?? 0) : 0;
      if (num1 != num2) {
        return num1.compareTo(num2);
      }
    }

    // If base versions are identical, compare build numbers if available
    final build1 = parts1.length > 1 ? (int.tryParse(parts1[1]) ?? 0) : 0;
    final build2 = parts2.length > 1 ? (int.tryParse(parts2[1]) ?? 0) : 0;
    return build1.compareTo(build2);
  }

  /// Queries GitHub Releases API and checks whether a newer version is published.
  Future<AppUpdateInfo> checkForUpdates() async {
    String currentVersion = '1.0.64';
    String currentBuild = '64';

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      currentVersion = packageInfo.version;
      currentBuild = packageInfo.buildNumber;
    } catch (e) {
      debugPrint('[AppUpdateService] PackageInfo load error: $e');
    }

    try {
      final response = await http.get(
        Uri.parse(releasesApiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'Nivara-Civic-App',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        return AppUpdateInfo(
          status: AppUpdateStatus.error,
          currentVersion: currentVersion,
          currentBuild: currentBuild,
          latestVersion: currentVersion,
          errorMessage: 'Unable to check for updates (HTTP ${response.statusCode}).',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawTagName = (data['tag_name'] as String?) ?? '';
      final cleanLatestVersion = rawTagName.replaceFirst(RegExp(r'^[vV]'), '').trim();
      final releaseTitle = data['name'] as String?;
      final releaseNotes = data['body'] as String?;
      final publishedStr = data['published_at'] as String?;
      final publishedAt = publishedStr != null ? DateTime.tryParse(publishedStr) : null;

      // Extract APK asset
      String? apkUrl;
      int? apkSize;
      String? apkName;

      final assets = (data['assets'] as List<dynamic>?) ?? [];
      // Prioritize "nivara-*.apk" or any ".apk"
      for (final rawAsset in assets) {
        if (rawAsset is Map<String, dynamic>) {
          final name = (rawAsset['name'] as String?) ?? '';
          if (name.toLowerCase().endsWith('.apk')) {
            apkName = name;
            apkUrl = rawAsset['browser_download_url'] as String?;
            apkSize = rawAsset['size'] as int?;
            if (name.toLowerCase().startsWith('nivara')) {
              break; // Found preferred primary asset
            }
          }
        }
      }

      // Semantic version check
      final isNewer = compareSemVer(currentVersion, cleanLatestVersion) < 0;

      return AppUpdateInfo(
        status: isNewer ? AppUpdateStatus.updateAvailable : AppUpdateStatus.upToDate,
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        latestVersion: cleanLatestVersion.isNotEmpty ? cleanLatestVersion : currentVersion,
        releaseTitle: releaseTitle,
        releaseNotes: releaseNotes,
        publishedAt: publishedAt,
        apkUrl: apkUrl ?? releasesWebUrl,
        apkSizeBytes: apkSize,
        apkFileName: apkName,
      );
    } catch (e) {
      debugPrint('[AppUpdateService] Check update exception: $e');
      return AppUpdateInfo(
        status: AppUpdateStatus.error,
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        latestVersion: currentVersion,
        errorMessage: 'Network check failed: ${e.toString().split('\n').first}',
      );
    }
  }

  /// Downloads the release APK directly with a streaming progress callback.
  Stream<DownloadProgress> downloadApkStream(String url) async* {
    final client = http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] = 'Nivara-Civic-App';

      final streamedResponse = await client.send(request);
      if (streamedResponse.statusCode != 200) {
        yield DownloadProgress(
          bytesReceived: 0,
          totalBytes: 0,
          percent: 0,
          error: 'Download server responded with HTTP ${streamedResponse.statusCode}',
        );
        return;
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();
      final targetFile = File('${tempDir.path}/nivara-update.apk');
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      sink = targetFile.openWrite();
      var received = 0;

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        received += chunk.length;
        final percent = totalBytes > 0 ? (received / totalBytes).clamp(0.0, 1.0) : 0.0;
        yield DownloadProgress(
          bytesReceived: received,
          totalBytes: totalBytes,
          percent: percent,
        );
      }

      await sink.flush();
      await sink.close();
      sink = null;

      yield DownloadProgress(
        bytesReceived: received,
        totalBytes: totalBytes,
        percent: 1.0,
        isDone: true,
        filePath: targetFile.path,
      );
    } catch (e) {
      debugPrint('[AppUpdateService] Download error: $e');
      yield DownloadProgress(
        bytesReceived: 0,
        totalBytes: 0,
        percent: 0,
        error: 'Download interrupted: $e',
      );
    } finally {
      if (sink != null) {
        await sink.close();
      }
      client.close();
    }
  }

  /// Prompts Android package installer via native FileProvider MethodChannel.
  /// Falls back to launching external browser if native installation is unavailable.
  Future<bool> installApk(String filePath, {String? fallbackUrl}) async {
    if (Platform.isAndroid) {
      try {
        final success = await _channel.invokeMethod<bool>(
          'installApk',
          {'filePath': filePath},
        );
        if (success == true) return true;
      } catch (e) {
        debugPrint('[AppUpdateService] Native install intent error: $e');
      }
    }

    // Fallback: open release download link directly
    final targetUrl = fallbackUrl ?? releasesWebUrl;
    final uri = Uri.parse(targetUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }

  /// Opens the release page in the system browser directly.
  Future<void> openReleasesInBrowser({String? customUrl}) async {
    final uri = Uri.parse(customUrl ?? releasesWebUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
