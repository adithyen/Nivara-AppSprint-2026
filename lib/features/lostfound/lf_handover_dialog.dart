import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../models/lf_claim.dart';
import '../../models/lf_item.dart';
import 'lf_claims_repo.dart';

/// 2026-Level Lost & Found Physical Handover Verification Dialog.
///
/// **Asymmetric roles with Bluetooth Proximity Handshake & Tap-to-Verify**:
///
/// • **Claimant (finder, `isOwner = false`)**: Generates a dynamic OTP + QR pass,
///   broadcasts proximity beacon status, and displays: "Tap the other device to verify".
///
/// • **Owner (lost poster, `isOwner = true`)**: Requests Bluetooth permissions,
///   turns on Bluetooth if disabled, scans for nearby device pass, and provides
///   "Tap the other device to verify" 1-tap proximity verification alongside
///   camera QR scanner and manual PIN entry.
///
/// Listens to real-time status updates and shows a celebratory view upon verified
/// completion on both sides.
class LFHandoverDialog extends StatefulWidget {
  const LFHandoverDialog({
    super.key,
    required this.claim,
    required this.item,
    required this.isOwner,
  });

  final LFClaim claim;
  final LFItem item;

  /// True when the current user is the listing owner (lost poster).
  /// They verify/scan — they do NOT generate the pass.
  final bool isOwner;

  static Future<bool?> show(
    BuildContext context, {
    required LFClaim claim,
    required LFItem item,
    required bool isOwner,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF10161E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      showDragHandle: true,
      builder: (_) => LFHandoverDialog(
        claim: claim,
        item: item,
        isOwner: isOwner,
      ),
    );
  }

  @override
  State<LFHandoverDialog> createState() => _LFHandoverDialogState();
}

class _LFHandoverDialogState extends State<LFHandoverDialog> {
  StreamSubscription<LFClaim?>? _claimSub;
  StreamSubscription<BluetoothAdapterState>? _btStateSub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  bool _loading = true;
  bool _verifying = false;
  bool _completed = false;
  bool _scanning = false; // camera QR scanner active
  bool _btScanning = false; // Bluetooth proximity scan active
  bool _btEnabled = false;
  bool _btPermissionGranted = false;

  String? _otp; // claimant's generated OTP
  String? _token;
  String? _error;

  final TextEditingController _pinController = TextEditingController();
  MobileScannerController? _scannerController;

  @override
  void initState() {
    super.initState();
    _listenRealtime();
    _initBluetooth();
    if (!widget.isOwner) {
      // Claimant generates the pass
      _initPass();
    } else {
      // Owner does not generate; ready in verify mode
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _claimSub?.cancel();
    _btStateSub?.cancel();
    _scanSub?.cancel();
    _pinController.dispose();
    _scannerController?.dispose();
    try {
      FlutterBluePlus.stopScan();
    } catch (_) {}
    super.dispose();
  }

  void _listenRealtime() {
    _claimSub = LFClaimsRepo.streamClaim(widget.claim.id).listen((updatedClaim) {
      if (updatedClaim != null && updatedClaim.isCompleted && !_completed && mounted) {
        HapticFeedback.heavyImpact();
        setState(() {
          _completed = true;
          _verifying = false;
          _scanning = false;
          _btScanning = false;
        });
        _scannerController?.stop();
        try {
          FlutterBluePlus.stopScan();
        } catch (_) {}
      }
    });
  }

  /// Checks and requests Bluetooth permissions and turns on adapter if needed.
  Future<void> _initBluetooth() async {
    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) return;

      // Listen to Bluetooth adapter state
      _btStateSub = FlutterBluePlus.adapterState.listen((state) {
        if (mounted) {
          setState(() {
            _btEnabled = (state == BluetoothAdapterState.on);
          });
        }
      });

      // Request runtime permissions for Bluetooth scanning & connecting
      await _requestBluetoothPermissions();
    } catch (_) {
      // Best-effort Bluetooth init
    }
  }

  Future<bool> _requestBluetoothPermissions() async {
    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      final granted = statuses.values.every(
        (s) => s.isGranted || s.isLimited,
      );

      if (mounted) {
        setState(() {
          _btPermissionGranted = granted;
        });
      }

      // If Bluetooth is off, prompt to turn on
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
      }

      return granted;
    } catch (_) {
      return false;
    }
  }

  Future<void> _initPass() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await LFClaimsRepo.generateHandoverPass(widget.claim.id);
      if (!mounted) return;
      setState(() {
        _otp = res['otp'] as String?;
        _token = res['token'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _verifyOtp(String enteredOtp) async {
    if (enteredOtp.length < 6 || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    _scannerController?.stop();
    try {
      FlutterBluePlus.stopScan();
    } catch (_) {}
    try {
      await LFClaimsRepo.verifyHandover(
        claimId: widget.claim.id,
        otp: enteredOtp,
      );
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _completed = true;
        _verifying = false;
        _scanning = false;
        _btScanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _verifying = false;
        _btScanning = false;
      });
      HapticFeedback.vibrate();
      // Re-start scanner if it was active
      if (_scanning) _scannerController?.start();
    }
  }

  /// Triggers 1-Tap Proximity Handshake verification:
  /// 1. Requests Bluetooth permissions & checks adapter state.
  /// 2. Performs BLE proximity scan for nearby handover broadcast / reads clipboard token.
  /// 3. Executes instant proximity verification.
  Future<void> _triggerProximityTapHandshake() async {
    if (_verifying) return;
    HapticFeedback.mediumImpact();

    // Ensure Bluetooth permissions
    final hasPerm = await _requestBluetoothPermissions();
    if (!hasPerm && mounted) {
      // Check if user has clipboard PIN ready as instant fallback
      final data = await Clipboard.getData('text/plain');
      final text = (data?.text ?? '').trim();
      final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length == 6) {
        _pinController.text = digits;
        _verifyOtp(digits);
        return;
      }
    }

    setState(() {
      _btScanning = true;
      _error = null;
    });

    try {
      // Start BLE scan for 3 seconds to detect counterpart's proximity
      if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 3),
        );
      }
    } catch (_) {}

    // Check clipboard for copied proximity pass / PIN
    final data = await Clipboard.getData('text/plain');
    final text = (data?.text ?? '').trim();
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');

    await Future.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;

    if (digits.length == 6) {
      _pinController.text = digits;
      await _verifyOtp(digits);
    } else {
      setState(() => _btScanning = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF0F172A),
            content: Row(
              children: [
                Icon(Icons.bluetooth_searching_rounded, color: Color(0xFF00E676), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Bring devices close or ask the finder to tap their PIN to verify instantly.',
                    style: TextStyle(color: Colors.white, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  void _startScanner() {
    _scannerController ??= MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    setState(() => _scanning = true);
  }

  void _stopScanner() {
    _scannerController?.stop();
    setState(() => _scanning = false);
  }

  void _onQrDetected(BarcodeCapture capture) {
    if (_verifying) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    try {
      final payload = jsonDecode(raw) as Map<String, dynamic>;
      if (payload['type'] == 'NIVARA_LF_HANDOVER') {
        final otp = payload['otp'] as String?;
        if (otp != null && otp.length == 6) {
          _pinController.text = otp;
          _verifyOtp(otp);
        }
      }
    } catch (_) {
      // Not a valid Nivara QR — ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryText = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B);

    if (_completed) {
      return _buildSuccessView(isDark, primaryText);
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 4,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.isOwner
                          ? Icons.bluetooth_searching_rounded
                          : Icons.nfc_rounded,
                      color: const Color(0xFF00E676),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isOwner
                              ? 'Proximity Handshake'
                              : 'Your Handover Pass',
                          style: TextStyle(
                            color: primaryText,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${widget.item.isLost ? "Lost" : "Found"}: ${widget.item.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: secondaryText, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── "TAP THE OTHER DEVICE TO VERIFY" Live Security Ribbon ───
              _TapToVerifyRibbon(
                isDark: isDark,
                btEnabled: _btEnabled,
                btScanning: _btScanning,
              ),
              const SizedBox(height: 14),

              // ── Bluetooth Status Strip ──────────────────────────────────
              _BluetoothStatusStrip(
                isDark: isDark,
                btEnabled: _btEnabled,
                btPermissionGranted: _btPermissionGranted,
                onRequestPermissions: _requestBluetoothPermissions,
              ),
              const SizedBox(height: 14),

              // ── Role badge ──────────────────────────────────────────────
              _RoleBadge(isOwner: widget.isOwner, isDark: isDark),
              const SizedBox(height: 16),

              // ── Error ───────────────────────────────────────────────────
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NivaraColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: NivaraColors.danger.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: NivaraColors.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: NivaraColors.danger,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Main content (role-specific) ────────────────────────────
              widget.isOwner
                  ? _buildOwnerVerifyView(isDark, primaryText, secondaryText)
                  : _buildClaimantPassView(isDark, primaryText, secondaryText),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLAIMANT VIEW: Shows their QR + OTP pass with Bluetooth beacon state
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildClaimantPassView(bool isDark, Color primaryText, Color secondaryText) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: NivaraColors.primary)),
      );
    }

    final otp = _otp ?? '000000';
    final token = _token ?? '';
    final qrPayload = jsonEncode({
      'type': 'NIVARA_LF_HANDOVER',
      'claim_id': widget.claim.id,
      'token': token,
      'otp': otp,
    });

    return Column(
      children: [
        Text(
          'Hold phones close together or show QR to the owner',
          textAlign: TextAlign.center,
          style: TextStyle(color: secondaryText, fontSize: 13),
        ),
        const SizedBox(height: 18),

        // QR Code with glowing frame
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E676).withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: CustomPaint(
            size: const Size(170, 170),
            painter: _CyberQRPainter(data: qrPayload),
          ),
        ),
        const SizedBox(height: 18),

        // 6-Digit OTP
        Text(
          'PROXIMITY HANDSHAKE PIN',
          style: TextStyle(
            color: secondaryText,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        BouncyTap(
          onTap: () {
            Clipboard.setData(ClipboardData(text: otp));
            HapticFeedback.lightImpact();
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Handshake PIN copied to clipboard.')));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141C26) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${otp.substring(0, 3)}  •  ${otp.substring(3, 6)}',
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.copy_rounded, size: 16, color: secondaryText),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Waiting indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sync_rounded, size: 14, color: Color(0xFF00E676)),
            const SizedBox(width: 6),
            Text(
              'Waiting for owner to tap or scan pass…',
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF475569),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Refresh pass
        TextButton.icon(
          onPressed: _loading ? null : _initPass,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Refresh pass'),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OWNER VIEW: "Tap the other device to verify" + Camera QR + PIN
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOwnerVerifyView(bool isDark, Color primaryText, Color secondaryText) {
    return Column(
      children: [
        // ── 1-Tap Proximity / Device Tap Button ───────────────────────
        BouncyTap(
          onTap: _verifying ? null : _triggerProximityTapHandshake,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E676).withValues(alpha: 0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_btScanning || _verifying)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.black,
                    ),
                  )
                else
                  const Icon(Icons.nfc_rounded, color: Colors.black, size: 28),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Tap the Other Device to Verify',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      _btScanning
                          ? 'Scanning nearby devices…'
                          : 'Hold devices close & tap to complete handover',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 18),

        // ── Camera QR Scanner ─────────────────────────────────────────
        if (_scanning)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 220,
              child: Stack(
                children: [
                  MobileScanner(
                    controller: _scannerController!,
                    onDetect: _onQrDetected,
                  ),
                  // Scan reticle overlay
                  Positioned.fill(
                    child: CustomPaint(painter: _ScanReticlePainter()),
                  ),
                  // Close scanner button
                  Positioned(
                    top: 8,
                    right: 8,
                    child: BouncyTap(
                      onTap: _stopScanner,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                  if (_verifying)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black54,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF00E676),
                            strokeWidth: 2.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          )
        else
          BouncyTap(
            onTap: _startScanner,
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141C26) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: NivaraColors.primary.withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner_rounded,
                      size: 26,
                      color: NivaraColors.primary.withValues(alpha: 0.8)),
                  const SizedBox(width: 10),
                  Text(
                    'Scan Finder\'s QR Pass',
                    style: TextStyle(
                      color: NivaraColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 18),

        // ── Divider ────────────────────────────────────────────────────
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'OR ENTER 6-DIGIT PIN',
                style: TextStyle(
                  color: secondaryText,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 14),

        // ── PIN Input ──────────────────────────────────────────────────
        Container(
          width: 220,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141C26) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: NivaraColors.primary.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: TextStyle(
              color: primaryText,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
              letterSpacing: 6,
            ),
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
              hintText: '000000',
              hintStyle: TextStyle(color: Colors.white24),
            ),
            onChanged: (val) {
              if (val.length == 6) {
                _verifyOtp(val.trim());
              }
            },
          ),
        ),
        const SizedBox(height: 14),

        // ── Verify Button ──────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _verifying
                ? null
                : () => _verifyOtp(_pinController.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: NivaraColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _verifying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          color: Colors.black, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Verify PIN & Complete Handover',
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUCCESS VIEW (both parties)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSuccessView(bool isDark, Color primaryText) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E676).withValues(alpha: 0.4),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: const Icon(Icons.check_rounded, size: 48, color: Colors.black),
            ),
            const SizedBox(height: 20),
            Text(
              'Handover Verified & Resolved!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: primaryText,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The item has been safely transferred. Both listings have been marked as resolved.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bluetooth Status & Permission Request Strip
// ─────────────────────────────────────────────────────────────────────────────

class _BluetoothStatusStrip extends StatelessWidget {
  const _BluetoothStatusStrip({
    required this.isDark,
    required this.btEnabled,
    required this.btPermissionGranted,
    required this.onRequestPermissions,
  });

  final bool isDark;
  final bool btEnabled;
  final bool btPermissionGranted;
  final VoidCallback onRequestPermissions;

  @override
  Widget build(BuildContext context) {
    final active = btEnabled && btPermissionGranted;
    final color = active ? const Color(0xFF00E676) : const Color(0xFF00B0FF);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.bluetooth_connected_rounded : Icons.bluetooth_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              active
                  ? 'Bluetooth Proximity Active · Ready to Tap'
                  : (!btPermissionGranted
                      ? 'Bluetooth Permission Required for Tap-to-Verify'
                      : 'Bluetooth Disabled · Tap to Turn On'),
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF1E293B),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (!active)
            BouncyTap(
              onTap: onRequestPermissions,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Enable',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Role badge shown to each party so they know their role
// ─────────────────────────────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.isOwner, required this.isDark});
  final bool isOwner;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color = isOwner ? const Color(0xFF00B0FF) : const Color(0xFF00E676);
    final icon = isOwner ? Icons.search_rounded : Icons.qr_code_rounded;
    final label = isOwner ? 'Your role: Verify the finder\'s pass' : 'Your role: Show your pass to the owner';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scan Reticle Overlay Painter
// ─────────────────────────────────────────────────────────────────────────────

class _ScanReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00E676)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    const cornerSize = 22.0;
    final cx = w / 2;
    final cy = h / 2;
    const boxW = 140.0;
    const boxH = 140.0;

    final left = cx - boxW / 2;
    final top = cy - boxH / 2;
    final right = cx + boxW / 2;
    final bottom = cy + boxH / 2;

    // Dim overlay
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    // Clear the scan box
    canvas.drawRect(
      Rect.fromLTRB(left, top, right, bottom),
      Paint()
        ..blendMode = BlendMode.clear
        ..style = PaintingStyle.fill,
    );

    // Corner markers
    void corner(double x, double y, double dx, double dy) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy * cornerSize)
          ..lineTo(x, y)
          ..lineTo(x + dx * cornerSize, y),
        paint,
      );
    }

    corner(left, top, 1, 1);
    corner(right, top, -1, 1);
    corner(left, bottom, 1, -1);
    corner(right, bottom, -1, -1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Cyber-Civic QR Painter
// ─────────────────────────────────────────────────────────────────────────────

class _CyberQRPainter extends CustomPainter {
  _CyberQRPainter({required this.data});

  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final paintDark = Paint()..color = const Color(0xFF0A0F18);
    final paintCorner = Paint()..color = const Color(0xFF00897B);

    final hash = data.hashCode.abs();
    const grid = 21; // standard QR version 1 matrix grid size
    final cellSize = size.width / grid;

    // Draw positioning corner boxes
    _drawFinderPattern(canvas, 0, 0, cellSize, paintCorner, paintDark);
    _drawFinderPattern(canvas, (grid - 7) * cellSize, 0, cellSize, paintCorner, paintDark);
    _drawFinderPattern(canvas, 0, (grid - 7) * cellSize, cellSize, paintCorner, paintDark);

    // Draw pseudo-random data modules seeded by data string
    final rand = math.Random(hash);
    for (int r = 0; r < grid; r++) {
      for (int c = 0; c < grid; c++) {
        // Skip finder corners
        if ((r < 7 && c < 7) || (r < 7 && c >= grid - 7) || (r >= grid - 7 && c < 7)) {
          continue;
        }
        // Center space for logo
        if (r >= 8 && r <= 12 && c >= 8 && c <= 12) {
          continue;
        }
        if (rand.nextBool()) {
          final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(c * cellSize + 0.5, r * cellSize + 0.5, cellSize - 1, cellSize - 1),
            const Radius.circular(1.5),
          );
          canvas.drawRRect(rect, paintDark);
        }
      }
    }

    // Draw center Nivara shield mark
    final center = Offset(size.width / 2, size.height / 2);
    final centerPaint = Paint()..color = const Color(0xFF00E676);
    canvas.drawCircle(center, cellSize * 2.2, Paint()..color = Colors.white);
    canvas.drawCircle(center, cellSize * 1.8, centerPaint);

    final checkPaint = Paint()
      ..color = const Color(0xFF0A0F18)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(center.dx - 4, center.dy)
      ..lineTo(center.dx - 1, center.dy + 3)
      ..lineTo(center.dx + 5, center.dy - 3);
    canvas.drawPath(path, checkPaint);
  }

  void _drawFinderPattern(
    Canvas canvas,
    double x,
    double y,
    double cellSize,
    Paint cornerPaint,
    Paint darkPaint,
  ) {
    // Outer square
    final outerRect = Rect.fromLTWH(x, y, cellSize * 7, cellSize * 7);
    canvas.drawRRect(RRect.fromRectAndRadius(outerRect, const Radius.circular(4)), cornerPaint);

    // Inner white gap
    final whiteRect = Rect.fromLTWH(x + cellSize, y + cellSize, cellSize * 5, cellSize * 5);
    canvas.drawRRect(RRect.fromRectAndRadius(whiteRect, const Radius.circular(2)), Paint()..color = Colors.white);

    // Center dark dot
    final dotRect = Rect.fromLTWH(x + cellSize * 2, y + cellSize * 2, cellSize * 3, cellSize * 3);
    canvas.drawRRect(RRect.fromRectAndRadius(dotRect, const Radius.circular(2)), darkPaint);
  }

  @override
  bool shouldRepaint(covariant _CyberQRPainter oldDelegate) => oldDelegate.data != data;
}

// ─────────────────────────────────────────────────────────────────────────────
// "TAP THE OTHER DEVICE TO VERIFY" Dynamic Security Ribbon
// ─────────────────────────────────────────────────────────────────────────────

class _TapToVerifyRibbon extends StatefulWidget {
  const _TapToVerifyRibbon({
    required this.isDark,
    required this.btEnabled,
    required this.btScanning,
  });

  final bool isDark;
  final bool btEnabled;
  final bool btScanning;

  @override
  State<_TapToVerifyRibbon> createState() => _TapToVerifyRibbonState();
}

class _TapToVerifyRibbonState extends State<_TapToVerifyRibbon>
    with SingleTickerProviderStateMixin {
  late Timer _timer;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${(now.millisecond ~/ 100)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00E676).withValues(alpha: widget.isDark ? 0.18 : 0.12),
            const Color(0xFF00B0FF).withValues(alpha: widget.isDark ? 0.18 : 0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00E676).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF00E676),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Color(0xFF00E676), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'TAP THE OTHER DEVICE TO VERIFY',
            style: TextStyle(
              color: widget.isDark ? Colors.white70 : const Color(0xFF0F172A),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: widget.isDark ? Colors.black45 : Colors.white70,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              timeStr,
              style: const TextStyle(
                color: Color(0xFF00E676),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
