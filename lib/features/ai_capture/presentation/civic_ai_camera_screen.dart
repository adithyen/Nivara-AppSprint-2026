import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/constants.dart';
import '../../../core/services/debug_logger.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/ola_maps_service.dart';
import '../../../core/theme.dart';
import '../../../models/enums.dart';
import '../../settings/language_controller.dart';
import '../models/civic_ai_models.dart';
import '../services/civic_ai_classifier_service.dart';
import 'civic_ai_review_sheet.dart';

/// Full-screen AI Civic Auto-Capture Scanner.
///
/// Continuously inspects the live camera stream for any of Nivara's 19 civic
/// hazard categories (potholes, open drains, garbage, waterlogging, etc.).
/// Automatically triggers an evidence capture when hazard is locked on and
/// held steady for 1.2 seconds.
class CivicAiCameraScreen extends ConsumerStatefulWidget {
  final ReportCategory? initialCategory;

  const CivicAiCameraScreen({super.key, this.initialCategory});

  @override
  ConsumerState<CivicAiCameraScreen> createState() => _CivicAiCameraScreenState();
}

class _CivicAiCameraScreenState extends ConsumerState<CivicAiCameraScreen>
    with SingleTickerProviderStateMixin {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _selectedCameraIndex = 0;
  bool _isCameraReady = false;
  bool _permissionDenied = false;
  bool _isTorchOn = false;

  ReportCategory? _targetedCategory;
  CivicAiDetection? _currentDetection;

  // Sensor-based physical stability detection
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  double _currentGForce = 0.0;
  bool _isDeviceSteady = true;
  int _steadyTicks = 0;

  // Timers & async state
  Timer? _steadyLockTimer;
  Timer? _nimScanTimer;
  bool _isNimScanInFlight = false;
  bool _isAnalyzing = false;
  bool _isCapturing = false;

  // Steady lock auto-capture state
  double _steadyLockProgress = 0.0;

  // Flash animation controller for shutter effect
  late AnimationController _flashAnimController;

  Position? _currentPosition;
  String? _currentAddress;

  @override
  void initState() {
    super.initState();
    _targetedCategory = widget.initialCategory;
    _flashAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    DebugLogger.instance.log(
      'AI-CAMERA',
      'CivicAiCameraScreen initialized (targetedCategory=${_targetedCategory?.wire ?? "none"})',
    );

    _initAccelerometer();
    _initPermissionsAndCamera();
    _fetchLocation();
  }

  void _initAccelerometer() {
    try {
      _accelSub = userAccelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 100),
      ).listen(
        (e) {
          final g = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z) / 9.80665;
          _currentGForce = g;
          // When phone is held steady on a scene, linear acceleration is < 0.28 g
          _isDeviceSteady = g < 0.28;
        },
        onError: (err) {
          DebugLogger.instance.log('SENSOR', 'Accelerometer error ($err), defaulting to steady');
          _isDeviceSteady = true;
        },
      );
      DebugLogger.instance.log('SENSOR', 'Accelerometer tracking initiated');
    } catch (e) {
      DebugLogger.instance.log('SENSOR', 'Accelerometer stream failed: $e');
      _isDeviceSteady = true;
    }
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _steadyLockTimer?.cancel();
    _nimScanTimer?.cancel();
    _controller?.dispose();
    _flashAnimController.dispose();
    DebugLogger.instance.log('AI-CAMERA', 'CivicAiCameraScreen disposed');
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    try {
      final pos = await const LocationService().current();
      _currentPosition = pos;
      if (pos != null) {
        final addr = await OlaMapsService.instance.reverseGeocode(
          lat: pos.latitude,
          lng: pos.longitude,
        );
        if (mounted) setState(() => _currentAddress = addr);
      }
    } catch (e) {
      DebugLogger.instance.log('AI-CAMERA', 'Location error: $e');
    }
  }

  Future<void> _initPermissionsAndCamera() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      setState(() {
        _permissionDenied = false;
      });
      await _initCameras();
    } else {
      setState(() {
        _permissionDenied = true;
      });
    }
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      // Prefer back camera
      _selectedCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (_selectedCameraIndex < 0) _selectedCameraIndex = 0;

      await _setupController(_cameras[_selectedCameraIndex]);
    } catch (e) {
      DebugLogger.instance.log('AI-CAMERA', 'Camera init error: $e');
    }
  }

  Future<void> _setupController(CameraDescription camera) async {
    await _controller?.dispose();
    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;

      setState(() => _isCameraReady = true);
      DebugLogger.instance.log(
        'AI-CAMERA',
        'Camera controller initialized: ${camera.lensDirection.name}, medium resolution',
      );

      _startPeriodicScan();
    } catch (e, stack) {
      DebugLogger.instance.error('AI-CAMERA', 'Controller setup error: $e', stack);
    }
  }

  void _startPeriodicScan() {
    _startSteadyLockTimer();
    _startNimScanLoop();
  }

  /// Physical steady-lock ticker. Every 250ms, if the device is held steady
  /// (low accelerometer jitter < 0.28 g), progress advances toward 1.0.
  /// When held steady on a scene for ~2.5 to 3.2 seconds, it automatically triggers capture!
  void _startSteadyLockTimer() {
    _steadyLockTimer?.cancel();
    _steadyLockTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _onSteadyLockTick();
    });
  }

  void _onSteadyLockTick() {
    if (_isCapturing || !_isCameraReady || _controller == null || !_controller!.value.isInitialized) {
      return;
    }

    if (_isDeviceSteady) {
      _steadyTicks++;
      // Progress increment per 250ms tick:
      // - Standard steady hold: 0.08 (~3.1s to 100%)
      // - Targeted category mode: 0.10 (~2.5s to 100%)
      // - NIM live detection confirmed: 0.18 (~1.4s to 100%)
      final double step = (_currentDetection != null && _currentDetection!.confidence >= 0.50)
          ? 0.18
          : (_targetedCategory != null ? 0.10 : 0.08);

      _steadyLockProgress = (_steadyLockProgress + step).clamp(0.0, 1.0);
      if (mounted) setState(() {});

      if (_steadyTicks % 4 == 0) {
        DebugLogger.instance.log(
          'STEADY',
          'Aim steady: g=${_currentGForce.toStringAsFixed(3)}, progress=${(_steadyLockProgress * 100).toInt()}%, ticks=$_steadyTicks',
        );
      }

      if (_steadyLockProgress >= 1.0) {
        DebugLogger.instance.log('AUTO-CAP', 'Steady-lock reached 100% → Firing auto-capture!');
        _triggerAutoCapture();
      }
    } else {
      // Movement or shaking detected
      if (_steadyLockProgress > 0) {
        _steadyTicks = 0;
        _steadyLockProgress = (_steadyLockProgress - 0.20).clamp(0.0, 1.0);
        if (mounted) setState(() {});
      }
    }
  }

  /// Background NIM Vision live scan loop. Dispatches frames to NVIDIA NIM
  /// every 2.5 seconds without blocking the steady-lock viewfinder.
  void _startNimScanLoop() {
    _nimScanTimer?.cancel();
    _nimScanTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      _runNimScan();
    });
  }

  Future<void> _runNimScan() async {
    if (_isNimScanInFlight || _isCapturing) return;
    if (_controller == null || !_controller!.value.isInitialized) return;

    _isNimScanInFlight = true;
    _isAnalyzing = true;
    if (mounted) setState(() {});

    try {
      final XFile snap = await _controller!.takePicture();
      final classifier = ref.read(civicAiClassifierServiceProvider);

      final detection = await classifier.scanLiveFrame(
        snap,
        hintCategory: _targetedCategory,
      );

      if (mounted) {
        setState(() {
          _currentDetection = detection;
        });

        if (detection != null &&
            detection.category != ReportCategory.other &&
            detection.confidence >= 0.50) {
          DebugLogger.instance.log(
            'NIM-SCAN',
            'NIM live detection confirmed: ${detection.category.wire} (${detection.confidence}) → snapping steady lock to 100%!',
          );
          _steadyLockProgress = 1.0;
          if (mounted) setState(() {});
          _triggerAutoCapture();
        }
      }
    } catch (e, stack) {
      DebugLogger.instance.error('NIM-SCAN', e, stack);
    } finally {
      _isNimScanInFlight = false;
      _isAnalyzing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _triggerAutoCapture() async {
    if (_isCapturing) return;
    _isCapturing = true;

    DebugLogger.instance.log('AUTO-CAP', 'Auto-capture triggered! Firing haptic impact...');
    HapticFeedback.heavyImpact();

    await _executeCapture(isAuto: true);
  }

  Future<void> _executeCapture({bool isAuto = false}) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    // Immediately stop steady-lock progress and NIM scan loop during capture/review
    _steadyLockTimer?.cancel();
    _nimScanTimer?.cancel();

    try {
      DebugLogger.instance.log('CAPTURE', 'Executing capture (isAuto=$isAuto)...');
      // Trigger shutter flash animation
      _flashAnimController.forward().then((_) => _flashAnimController.reverse());

      final XFile photo = await _controller!.takePicture();
      DebugLogger.instance.log('CAPTURE', 'Photo taken: ${photo.path}');

      // Deep AI classification on the captured full-res photo
      final classifier = ref.read(civicAiClassifierServiceProvider);
      final finalDetection = await classifier.classifyCapturedPhoto(
        photo,
        hintCategory: _currentDetection?.category ?? _targetedCategory,
      );
      DebugLogger.instance.log(
        'CAPTURE',
        'Classification complete: ${finalDetection.category.wire} (conf: ${finalDetection.confidence})',
      );

      final payload = CivicAiCapturePayload(
        photoPath: photo.path,
        detection: finalDetection,
        lat: _currentPosition?.latitude ?? kDefaultLat,
        lng: _currentPosition?.longitude ?? kDefaultLng,
        address: _currentAddress,
        capturedAt: DateTime.now(),
      );

      if (!mounted) return;

      DebugLogger.instance.log('CAPTURE', 'Displaying CivicAiReviewSheet modal bottom sheet');
      // Present the post-capture review modal sheet
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => CivicAiReviewSheet(
          payload: payload,
          onRetake: () {
            Navigator.of(ctx).pop();
            _resetForNextCapture();
          },
        ),
      );

      _resetForNextCapture();
    } catch (e, stack) {
      DebugLogger.instance.error('CAPTURE', e, stack);
      _resetForNextCapture();
    }
  }

  void _resetForNextCapture() {
    ref.read(civicAiClassifierServiceProvider).resetTracking();
    if (mounted) {
      setState(() {
        _isCapturing = false;
        _steadyLockProgress = 0.0;
        _steadyTicks = 0;
        _currentDetection = null;
      });
      DebugLogger.instance.log('CAM-RESET', 'Reset completed, restarting scan cycles.');
      _startSteadyLockTimer();
      _startNimScanLoop();
    }
  }

  Future<void> _toggleTorch() async {
    if (_controller == null) return;
    try {
      final newMode = _isTorchOn ? FlashMode.off : FlashMode.torch;
      await _controller!.setFlashMode(newMode);
      setState(() => _isTorchOn = !_isTorchOn);
    } catch (e) {
      debugPrint('[CivicAiCameraScreen] Torch error: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _setupController(_cameras[_selectedCameraIndex]);
  }

  @override
  Widget build(BuildContext context) {
    final currentLang = ref.watch(languageControllerProvider);
    final isMalayalam = currentLang == AppLanguage.ml;

    if (_permissionDenied) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0F18),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.camera_alt_outlined, size: 64, color: Colors.white54),
                const SizedBox(height: 18),
                Text(
                  isMalayalam ? 'ക്യാമറ അനുമതി ആവശ്യമാണ്' : 'Camera Permission Required',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isMalayalam
                      ? 'റോഡിലെ കുഴികളും ഡ്രെയിനേജും തിരിച്ചറിയാൻ ക്യാമറ അനുമതി നൽകുക.'
                      : 'Grant camera access to automatically detect potholes, open drains, and civic hazards.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _initPermissionsAndCamera,
                  icon: const Icon(Icons.security_rounded),
                  label: Text(isMalayalam ? 'അനുമതി നൽകുക' : 'Grant Permission'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NivaraColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isCameraReady || _controller == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0F18),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: NivaraColors.primary),
              SizedBox(height: 16),
              Text(
                'Initializing Civic AI Vision Engine...',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Live Viewfinder
          Center(
            child: CameraPreview(_controller!),
          ),

          // 2. Cybernetic Reticle & Detection Bounding Box Overlay
          if (_currentDetection != null && _currentDetection!.boundingBox != null)
            _buildDetectionOverlay(_currentDetection!),

          // 3. Shutter Flash Animation Overlay
          AnimatedBuilder(
            animation: _flashAnimController,
            builder: (context, child) {
              return IgnorePointer(
                child: Container(
                  color: Colors.white.withValues(alpha: _flashAnimController.value * 0.9),
                ),
              );
            },
          ),

          // 4. Top Control Bar (Back, Torch, Switch Camera, Category Filter)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopControlBar(currentLang),
          ),

          // 5. Steady Lock Auto-Capture Meter / Analyzing HUD / Idle Hint
          if (_steadyLockProgress > 0)
            Positioned(
              top: 140,
              left: 32,
              right: 32,
              child: _buildSteadyLockHud(isMalayalam),
            )
          else if (_isAnalyzing)
            Positioned(
              top: 140,
              left: 40,
              right: 40,
              child: _buildAnalyzingHud(isMalayalam),
            )
          else if (_currentDetection == null)
            Positioned(
              top: 150,
              left: 40,
              right: 40,
              child: _buildIdleHint(isMalayalam),
            ),

          // 6. Bottom Capture Controls & Category Override
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomControlHud(currentLang),
          ),
        ],
      ),
    );
  }

  Widget _buildTopControlBar(AppLanguage currentLang) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 10, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.8),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: NivaraColors.primary.withValues(alpha: 0.6)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, color: NivaraColors.primary, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'AI AUTO-CAPTURE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Diagnostic Logs Toggle
              IconButton(
                icon: const Icon(Icons.receipt_long_rounded, color: Colors.cyanAccent),
                tooltip: 'Diagnostic Logs',
                onPressed: () => _showDiagnosticLogs(context),
              ),
              // Torch Toggle
              IconButton(
                icon: Icon(
                  _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: _isTorchOn ? Colors.amberAccent : Colors.white,
                ),
                onPressed: _toggleTorch,
              ),
              // Lens Switch
              if (_cameras.length > 1)
                IconButton(
                  icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
                  onPressed: _switchCamera,
                ),
            ],
          ),

          const SizedBox(height: 6),

          // Category Quick-Filter Horizontal Scroll
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildCategoryFilterChip(
                  label: currentLang == AppLanguage.ml ? 'ഓട്ടോ (എല്ലാം)' : 'Auto (All 19)',
                  isSelected: _targetedCategory == null,
                  onTap: () => setState(() => _targetedCategory = null),
                ),
                ...ReportCategory.values.map((cat) {
                  return _buildCategoryFilterChip(
                    label: cat.localizedName(currentLang),
                    isSelected: _targetedCategory == cat,
                    onTap: () => setState(() => _targetedCategory = cat),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? NivaraColors.primary.withValues(alpha: 0.85)
              : Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white24,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildDetectionOverlay(CivicAiDetection detection) {
    final box = detection.boundingBox!;
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    final rectLeft = box.left * screenW;
    final rectTop = box.top * screenH;
    final rectWidth = box.width * screenW;
    final rectHeight = box.height * screenH;

    final isHighConf = detection.isHighConfidence;
    final color = isHighConf ? const Color(0xFF00FFCC) : Colors.amberAccent;

    return Positioned(
      left: rectLeft,
      top: rectTop,
      width: rectWidth,
      height: rectHeight,
      child: IgnorePointer(
        child: Stack(
          children: [
            // Cybernetic corner brackets
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: color.withValues(alpha: 0.8), width: 2),
                borderRadius: BorderRadius.circular(12),
                color: color.withValues(alpha: 0.08),
              ),
            ),
            // Floating Detection Badge
            Positioned(
              top: 6,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isHighConf ? Icons.radar_rounded : Icons.search_rounded,
                      color: color,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${detection.category.label.toUpperCase()} ${(detection.confidence * 100).toInt()}%',
                      style: TextStyle(
                        color: color,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSteadyLockHud(bool isMalayalam) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F18).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00FFCC), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00FFCC).withValues(alpha: 0.35),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              value: _steadyLockProgress,
              strokeWidth: 3.5,
              color: const Color(0xFF00FFCC),
              backgroundColor: Colors.white24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isMalayalam ? 'ക്യാമറ ചലിപ്പിക്കാതെ പിടിക്കുക...' : 'HOLD STEADY...',
                  style: const TextStyle(
                    color: Color(0xFF00FFCC),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isMalayalam
                      ? 'AI ഓട്ടോ-ക്യാപ്ചർ ചെയ്യുന്നു (${(_steadyLockProgress * 100).toInt()}%)'
                      : 'AI Auto-Lock Capturing Proof (${(_steadyLockProgress * 100).toInt()}%)',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzingHud(bool isMalayalam) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F18).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00FFCC), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00FFCC).withValues(alpha: 0.25),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF00FFCC),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isMalayalam ? 'AI വിശകലനം ചെയ്യുന്നു...' : 'AI SCANNING...',
                  style: const TextStyle(
                    color: Color(0xFF00FFCC),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  isMalayalam
                      ? 'NIM 11B Vision ഫ്രേം പരിശോധിക്കുന്നു'
                      : 'Llama 3.2-11B Vision analyzing frame',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleHint(bool isMalayalam) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_rounded, color: Colors.white54, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              isMalayalam
                  ? 'പ്രശ്നം ഇല്ലെന്ന് AI തീർച്ചപ്പെടുത്തി'
                  : 'No civic hazard detected — scanning every 1.5s',
              style: const TextStyle(color: Colors.white60, fontSize: 11.5),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControlHud(AppLanguage currentLang) {
    final isMalayalam = currentLang == AppLanguage.ml;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Guidance prompt
          Text(
            _currentDetection != null
                ? '${_currentDetection!.category.localizedName(currentLang)}: ${_currentDetection!.title}'
                : (isMalayalam
                    ? 'ക്യാമറ പ്രശ്നത്തിലേക്ക് തിരിക്കുക, 1.5 സെക്കൻഡ് ഇടവേളയിൽ AI പരിശോധിക്കും'
                    : 'Point at a civic issue — AI checks every 1.5 seconds'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _currentDetection != null ? const Color(0xFF00FFCC) : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 18),

          // Main Shutter Button
          GestureDetector(
            onTap: _isCapturing ? null : () => _executeCapture(isAuto: false),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: NivaraColors.primary.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: _isCapturing
                      ? const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: NivaraColors.primary,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.auto_awesome_rounded,
                          color: NivaraColors.primary,
                          size: 30,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isMalayalam
                ? 'ടാപ്പ് ചെയ്ത് ഇപ്പോൾ ഫോട്ടോ എടുക്കാം'
                : "Tap to capture now \u2014 AI will verify it's a real issue",
            style: const TextStyle(color: Colors.white54, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  void _showDiagnosticLogs(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final recentLogs = DebugLogger.instance.recent;
        final allText = recentLogs.join('\n');
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.terminal_rounded, color: Colors.cyanAccent, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'AI Diagnostic Console',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 20),
                        tooltip: 'Copy all logs',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: allText));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Copied all logs to clipboard!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  Text(
                    'File: ${DebugLogger.instance.resolvedPath}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF030712),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: recentLogs.isEmpty
                          ? const Center(
                              child: Text(
                                'No logs recorded yet. Point camera at a scene.',
                                style: TextStyle(color: Colors.white38, fontSize: 12),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: recentLogs.length,
                              itemBuilder: (ctx, idx) {
                                final line = recentLogs[idx];
                                Color textColor = Colors.white70;
                                if (line.contains('[ERROR]')) {
                                  textColor = Colors.redAccent;
                                } else if (line.contains('[AUTO-CAP]') || line.contains('[CAPTURE]')) {
                                  textColor = Colors.amberAccent;
                                } else if (line.contains('[NIM-API]') || line.contains('[NIM-SCAN]')) {
                                  textColor = Colors.cyanAccent;
                                } else if (line.contains('[STEADY]')) {
                                  textColor = Colors.lightGreenAccent;
                                }
                                return Text(
                                  line,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10.5,
                                    color: textColor,
                                    height: 1.35,
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: allText));
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('All logs copied to clipboard! Paste in chat.'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('COPY ALL LOGS TO CLIPBOARD'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NivaraColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
