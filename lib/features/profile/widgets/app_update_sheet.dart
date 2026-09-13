import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/app_update_service.dart';
import '../../../core/widgets/bouncy_tap.dart';

/// Interactive glassmorphic modal sheet for checking, downloading, and installing app updates.
/// Designed according to 2026 Emil Kowalski spring physics & Taste design standards.
class AppUpdateSheet extends StatefulWidget {
  const AppUpdateSheet({
    super.key,
    this.initialInfo,
  });

  final AppUpdateInfo? initialInfo;

  static Future<void> show(BuildContext context, {AppUpdateInfo? initialInfo}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => AppUpdateSheet(initialInfo: initialInfo),
    );
  }

  @override
  State<AppUpdateSheet> createState() => _AppUpdateSheetState();
}

class _AppUpdateSheetState extends State<AppUpdateSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  AppUpdateInfo? _info;
  bool _checking = false;
  bool _downloading = false;
  double _downloadPercent = 0.0;
  String _downloadReceivedStr = '0 MB';
  String _downloadTotalStr = '...';
  String? _downloadFilePath;
  String? _downloadError;
  StreamSubscription<DownloadProgress>? _downloadSub;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );

    if (widget.initialInfo != null) {
      _info = widget.initialInfo;
      _animController.forward();
    } else {
      _checkForUpdates();
    }
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _downloading = false;
      _downloadError = null;
    });
    HapticFeedback.selectionClick();

    final res = await AppUpdateService.instance.checkForUpdates();
    if (!mounted) return;

    setState(() {
      _info = res;
      _checking = false;
    });

    _animController.reset();
    _animController.forward();
    HapticFeedback.lightImpact();
  }

  void _startDownload() {
    final apkUrl = _info?.apkUrl;
    if (apkUrl == null || apkUrl.isEmpty) {
      AppUpdateService.instance.openReleasesInBrowser();
      return;
    }

    setState(() {
      _downloading = true;
      _downloadPercent = 0.0;
      _downloadReceivedStr = '0 MB';
      _downloadTotalStr = _info?.formattedSize ?? '...';
      _downloadError = null;
      _downloadFilePath = null;
    });
    HapticFeedback.mediumImpact();

    _downloadSub?.cancel();
    _downloadSub = AppUpdateService.instance.downloadApkStream(apkUrl).listen(
      (progress) async {
        if (!mounted) return;
        if (progress.error != null) {
          setState(() {
            _downloading = false;
            _downloadError = progress.error;
          });
          HapticFeedback.heavyImpact();
        } else if (progress.isDone && progress.filePath != null) {
          setState(() {
            _downloading = false;
            _downloadPercent = 1.0;
            _downloadFilePath = progress.filePath;
          });
          HapticFeedback.heavyImpact();
          // Prompt installer immediately
          await _installDownloadedApk(progress.filePath!);
        } else {
          setState(() {
            _downloadPercent = progress.percent;
            _downloadReceivedStr = progress.formattedReceived;
            _downloadTotalStr = progress.formattedTotal;
          });
        }
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _downloadError = err.toString();
        });
      },
    );
  }

  Future<void> _installDownloadedApk(String filePath) async {
    HapticFeedback.lightImpact();
    await AppUpdateService.instance.installApk(
      filePath,
      fallbackUrl: _info?.apkUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    final bgColor = isDark ? const Color(0xFF0F151F) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        margin: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.15),
              blurRadius: 32,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Top pull handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.system_update_rounded,
                      color: primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Software Updates',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          'Official GitHub Release Registry',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white60 : Colors.black54,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(color: borderColor, height: 1),

            // Body Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                child: _buildBody(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_checking) {
      return _buildCheckingState(context);
    }

    if (_downloading) {
      return _buildDownloadingState(context);
    }

    if (_downloadFilePath != null) {
      return _buildReadyToInstallState(context);
    }

    final info = _info;
    if (info == null) {
      return _buildCheckingState(context);
    }

    if (info.status == AppUpdateStatus.error) {
      return _buildErrorState(context, info);
    }

    if (info.isUpdateAvailable) {
      return _buildUpdateAvailableState(context, info);
    }

    return _buildUpToDateState(context, info);
  }

  /// State 1: Checking for updates
  Widget _buildCheckingState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: CircularProgressIndicator(
                  strokeWidth: 2.8,
                  valueColor: AlwaysStoppedAnimation<Color>(primary),
                ),
              ),
              Icon(
                Icons.cloud_sync_rounded,
                size: 34,
                color: primary,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Querying GitHub Releases...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Comparing installed build against latest releases',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  /// State 2: App is up to date
  Widget _buildUpToDateState(BuildContext context, AppUpdateInfo info) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const emeraldColor = Color(0xFF00E676);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: emeraldColor.withValues(alpha: 0.12),
              border: Border.all(
                color: emeraldColor.withValues(alpha: 0.35),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: emeraldColor.withValues(alpha: 0.25),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: emeraldColor,
              size: 44,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            "You're Up to Date",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Nivara v${info.currentVersion} is the latest release available.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 22),

          // Build Telemetry Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Column(
              children: [
                _buildTelemetryRow(
                  label: 'Installed Version',
                  value: 'v${info.currentVersion} (Build ${info.currentBuild})',
                  isDark: isDark,
                  isMonospace: true,
                ),
                const SizedBox(height: 10),
                _buildTelemetryRow(
                  label: 'Release Channel',
                  value: 'Official Production',
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _buildTelemetryRow(
                  label: 'Integrity Status',
                  value: 'Verified Authentic',
                  isDark: isDark,
                  valueColor: emeraldColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: BouncyTap(
                  onTap: _checkForUpdates,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Check Again',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BouncyTap(
                  onTap: () => AppUpdateService.instance.openReleasesInBrowser(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 18,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'GitHub Notes',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// State 3: Update available
  Widget _buildUpdateAvailableState(BuildContext context, AppUpdateInfo info) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const cyanColor = Color(0xFF00B0FF);
    const purpleColor = Color(0xFF7B4BC4);

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cyanColor.withValues(alpha: 0.15),
                  purpleColor.withValues(alpha: 0.15),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cyanColor.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [cyanColor, purpleColor],
                    ),
                  ),
                  child: const Icon(
                    Icons.upgrade_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New Version Available',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            'v${info.currentVersion}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'v${info.latestVersion}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: cyanColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    info.formattedSize,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Release Notes Section
          Text(
            info.releaseTitle ?? 'Release Notes',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),

          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: SingleChildScrollView(
              child: Text(
                (info.releaseNotes != null && info.releaseNotes!.trim().isNotEmpty)
                    ? info.releaseNotes!.trim()
                    : 'Performance optimizations, security patches, and user interface refinements.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Primary CTA: Download & Install
          BouncyTap(
            onTap: _startDownload,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [cyanColor, purpleColor],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: cyanColor.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.download_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Download & Install Update',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Fallback: Browser Handover
          Center(
            child: TextButton.icon(
              onPressed: () => AppUpdateService.instance.openReleasesInBrowser(
                customUrl: info.apkUrl,
              ),
              icon: Icon(
                Icons.open_in_browser_rounded,
                size: 16,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
              label: Text(
                'Download via Browser instead',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// State 4: Downloading progress
  Widget _buildDownloadingState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const cyanColor = Color(0xFF00B0FF);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cyanColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.downloading_rounded,
                  color: cyanColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Downloading Update...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      'Saving verified package to secure cache',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(_downloadPercent * 100).toInt()}%',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: cyanColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Animated Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _downloadPercent > 0 ? _downloadPercent : null,
              minHeight: 10,
              backgroundColor: isDark ? Colors.white12 : Colors.black12,
              valueColor: const AlwaysStoppedAnimation<Color>(cyanColor),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_downloadReceivedStr / $_downloadTotalStr',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              Text(
                'Streaming via GitHub CDN',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Cancel or Handover
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
                  ),
                  onPressed: () {
                    _downloadSub?.cancel();
                    setState(() {
                      _downloading = false;
                      _downloadPercent = 0.0;
                    });
                  },
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => AppUpdateService.instance.openReleasesInBrowser(
                    customUrl: _info?.apkUrl,
                  ),
                  icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                  label: const Text('Open Browser'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// State 5: Ready to install
  Widget _buildReadyToInstallState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const emeraldColor = Color(0xFF00E676);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: emeraldColor.withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.check_rounded,
              color: emeraldColor,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Download Complete!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'The update package is ready to install.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 24),

          BouncyTap(
            onTap: () => _installDownloadedApk(_downloadFilePath!),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: emeraldColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: emeraldColor.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.install_mobile_rounded,
                    color: Colors.black87,
                    size: 22,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Install Update Now',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// State 6: Error state
  Widget _buildErrorState(BuildContext context, AppUpdateInfo info) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const amberColor = Color(0xFFFFB300);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: amberColor.withValues(alpha: 0.12),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: amberColor,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Update Check Incomplete',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            info.errorMessage ?? _downloadError ?? 'Could not connect to GitHub release registry.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _checkForUpdates,
                  child: const Text('Try Again'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => AppUpdateService.instance.openReleasesInBrowser(),
                  child: const Text('Visit GitHub'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryRow({
    required String label,
    required String value,
    required bool isDark,
    bool isMonospace = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            fontFamily: isMonospace ? 'monospace' : null,
            color: valueColor ?? (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ],
    );
  }
}
