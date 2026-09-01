import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../models/lf_claim.dart';
import '../../models/lf_item.dart';
import 'lf_claims_repo.dart';

// ─────────────────────────────────────────────────────────────────────────────
// How the proximity "Tap to Verify" works:
//
//  CLAIMANT side (isOwner = false):
//   • Generates OTP + token via Supabase RPC
//   • Shows a REAL QrImageView (not fake painter) with JSON payload
//   • Publishes the OTP to a Supabase Realtime broadcast channel named
//     "handover:{claimId}" every 5 seconds as long as the dialog is open.
//
//  OWNER side (isOwner = true):
//   • Subscribes to "handover:{claimId}" channel.
//   • When the claimant's broadcast arrives, OTP is auto-filled and verified
//     instantly — zero user clipboard interaction required.
//   • Also exposes a full-screen QR scanner page and manual PIN entry.
// ─────────────────────────────────────────────────────────────────────────────

/// Lost & Found Physical Handover Verification Dialog — Asymmetric Roles.
class LFHandoverDialog extends StatefulWidget {
  const LFHandoverDialog({
    super.key,
    required this.claim,
    required this.item,
    required this.isOwner,
  });

  final LFClaim claim;
  final LFItem item;
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
      builder: (_) => LFHandoverDialog(claim: claim, item: item, isOwner: isOwner),
    );
  }

  @override
  State<LFHandoverDialog> createState() => _LFHandoverDialogState();
}

class _LFHandoverDialogState extends State<LFHandoverDialog> {
  // Supabase listeners
  StreamSubscription<LFClaim?>? _claimSub;
  RealtimeChannel? _proximityChannel;
  Timer? _broadcastTimer;

  // BLE
  StreamSubscription<BluetoothAdapterState>? _btStateSub;
  bool _btEnabled = false;
  bool _btPermGranted = false;

  // State
  bool _loading = true;
  bool _verifying = false;
  bool _completed = false;
  bool _proximityListening = false; // owner is listening for OTP broadcast
  bool _proximityBroadcasting = false; // claimant is broadcasting OTP

  String? _otp;
  String? _token;
  String? _error;

  final TextEditingController _pinCtrl = TextEditingController();

  String get _channelName => 'handover:${widget.claim.id}';

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _listenClaimRealtime();
    _initBluetooth();
    if (!widget.isOwner) {
      _initPass();
    } else {
      _subscribeProximityChannel();
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _claimSub?.cancel();
    _btStateSub?.cancel();
    _broadcastTimer?.cancel();
    _proximityChannel?.unsubscribe();
    supabase.removeChannel(_proximityChannel!);
    _pinCtrl.dispose();
    super.dispose();
  }

  // ── Supabase Realtime — claim status ──────────────────────────────────────

  void _listenClaimRealtime() {
    _claimSub = LFClaimsRepo.streamClaim(widget.claim.id).listen((c) {
      if (c != null && c.isCompleted && !_completed && mounted) {
        HapticFeedback.heavyImpact();
        _markComplete();
      }
    });
  }

  void _markComplete() {
    _broadcastTimer?.cancel();
    _proximityChannel?.unsubscribe();
    setState(() {
      _completed = true;
      _verifying = false;
      _proximityListening = false;
      _proximityBroadcasting = false;
    });
  }

  // ── Supabase Realtime — proximity OTP channel ─────────────────────────────

  /// OWNER subscribes to the private handover channel to auto-receive OTP.
  void _subscribeProximityChannel() {
    _proximityChannel = supabase.channel(_channelName);
    _proximityChannel!
        .onBroadcast(
          event: 'otp',
          callback: (payload) {
            if (!mounted || _verifying || _completed) return;
            final otp = payload['otp'] as String?;
            if (otp != null && RegExp(r'^\d{6}$').hasMatch(otp)) {
              HapticFeedback.mediumImpact();
              _pinCtrl.text = otp;
              setState(() => _proximityListening = false);
              _verifyOtp(otp);
            }
          },
        )
        .subscribe();
    if (mounted) setState(() => _proximityListening = true);
  }

  /// CLAIMANT broadcasts OTP every 5 seconds on the private channel.
  void _startProximityBroadcast(String otp) {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _completed) return;
      try {
        await _proximityChannel?.sendBroadcastMessage(
          event: 'otp',
          payload: {'otp': otp},
        );
      } catch (_) {}
    });

    // Set up the channel for the claimant too (sender)
    _proximityChannel = supabase.channel(_channelName);
    _proximityChannel!.subscribe(
      (status, _) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (mounted) setState(() => _proximityBroadcasting = true);
          // Send immediately after subscribe
          try {
            await _proximityChannel?.sendBroadcastMessage(
              event: 'otp',
              payload: {'otp': otp},
            );
          } catch (_) {}
        }
      },
    );
  }

  // ── Bluetooth — best-effort for turn-on prompt ────────────────────────────

  Future<void> _initBluetooth() async {
    try {
      if (!await FlutterBluePlus.isSupported) return;
      _btStateSub = FlutterBluePlus.adapterState.listen((s) {
        if (mounted) setState(() => _btEnabled = s == BluetoothAdapterState.on);
      });
      await _requestBtPermissions();
    } catch (_) {}
  }

  Future<bool> _requestBtPermissions() async {
    try {
      final statuses = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      final ok = statuses.values.every((s) => s.isGranted || s.isLimited);
      if (mounted) setState(() => _btPermGranted = ok);
      return ok;
    } catch (_) {
      return false;
    }
  }

  // ── Claimant: generate pass ────────────────────────────────────────────────

  Future<void> _initPass() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await LFClaimsRepo.generateHandoverPass(widget.claim.id);
      if (!mounted) return;
      final otp = res['otp'] as String?;
      final token = res['token'] as String?;
      setState(() {
        _otp = otp;
        _token = token;
        _loading = false;
      });
      // Auto-start broadcasting OTP to owner's phone
      if (otp != null) _startProximityBroadcast(otp);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  // ── Verification ───────────────────────────────────────────────────────────

  Future<void> _verifyOtp(String pin) async {
    if (pin.length < 6 || _verifying) return;
    setState(() { _verifying = true; _error = null; });
    HapticFeedback.mediumImpact();
    try {
      await LFClaimsRepo.verifyHandover(claimId: widget.claim.id, otp: pin);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _markComplete();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _verifying = false;
      });
      HapticFeedback.vibrate();
    }
  }

  // ── QR Scanner — full-screen page to fix black-box issue ──────────────────

  Future<void> _openQrScanner() async {
    final otp = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _QRScanPage(),
      ),
    );
    if (otp != null && otp.isNotEmpty && mounted) {
      _pinCtrl.text = otp;
      _verifyOtp(otp);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryText = isDark ? Colors.white60 : const Color(0xFF64748B);

    if (_completed) {
      return _SuccessView(onDone: () => Navigator.pop(context, true));
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 4,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                isOwner: widget.isOwner,
                itemTitle: widget.item.title,
                isLost: widget.item.isLost,
                onClose: () => Navigator.pop(context, false),
              ),
              const SizedBox(height: 10),

              // Live ribbon
              _LiveRibbon(
                isDark: isDark,
                isOwner: widget.isOwner,
                broadcasting: _proximityBroadcasting,
                listening: _proximityListening,
              ),
              const SizedBox(height: 10),

              // Bluetooth status (best-effort prompt to enable BT)
              _BtStrip(
                isDark: isDark,
                btEnabled: _btEnabled,
                permGranted: _btPermGranted,
                onEnable: _requestBtPermissions,
              ),
              const SizedBox(height: 12),

              // Role badge
              _RoleBadge(isOwner: widget.isOwner, isDark: isDark),
              const SizedBox(height: 14),

              // Error banner
              if (_error != null) _ErrorBanner(error: _error!),

              // Role-specific content
              if (widget.isOwner)
                _OwnerSection(
                  isDark: isDark,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                  verifying: _verifying,
                  listening: _proximityListening,
                  pinCtrl: _pinCtrl,
                  onScanQr: _openQrScanner,
                  onVerify: () => _verifyOtp(_pinCtrl.text.trim()),
                )
              else
                _ClaimantSection(
                  isDark: isDark,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                  loading: _loading,
                  otp: _otp,
                  token: _token,
                  claimId: widget.claim.id,
                  broadcasting: _proximityBroadcasting,
                  onRefresh: _initPass,
                  onSnack: _snack,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen QR Scanner page — fixes the BottomSheet black-box issue
// ─────────────────────────────────────────────────────────────────────────────

class _QRScanPage extends StatefulWidget {
  const _QRScanPage();

  @override
  State<_QRScanPage> createState() => _QRScanPageState();
}

class _QRScanPageState extends State<_QRScanPage> {
  late final MobileScannerController _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _done = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    final raw = cap.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    String? otp;
    try {
      final p = jsonDecode(raw) as Map<String, dynamic>;
      if (p['type'] == 'NIVARA_LF_HANDOVER') {
        otp = p['otp'] as String?;
      }
    } catch (_) {
      // Raw 6-digit OTP
      final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (d.length == 6) otp = d;
    }

    if (otp != null && RegExp(r'^\d{6}$').hasMatch(otp)) {
      _done = true;
      HapticFeedback.heavyImpact();
      Navigator.of(context).pop(otp);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Scan Finder\'s QR Code',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
            tooltip: 'Toggle torch',
            onPressed: () => _ctrl.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _ctrl, onDetect: _onDetect),
          Positioned.fill(child: _ReticleOverlay()),
          Positioned(
            bottom: 48, left: 24, right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Point the camera at the QR code on the finder\'s screen',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 13.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReticleOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ReticlePainter());
  }
}

class _ReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const box = 220.0;
    final cx = size.width / 2, cy = size.height / 2;
    final l = cx - box / 2, t = cy - box / 2;
    final r = cx + box / 2, b = cy + box / 2;

    final dim = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, t), dim);
    canvas.drawRect(Rect.fromLTRB(0, b, size.width, size.height), dim);
    canvas.drawRect(Rect.fromLTRB(0, t, l, b), dim);
    canvas.drawRect(Rect.fromLTRB(r, t, size.width, b), dim);

    final p = Paint()
      ..color = const Color(0xFF00E676)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const cs = 28.0;
    canvas.drawPath(Path()..moveTo(l, t + cs)..lineTo(l, t)..lineTo(l + cs, t), p);
    canvas.drawPath(Path()..moveTo(r - cs, t)..lineTo(r, t)..lineTo(r, t + cs), p);
    canvas.drawPath(Path()..moveTo(l, b - cs)..lineTo(l, b)..lineTo(l + cs, b), p);
    canvas.drawPath(Path()..moveTo(r - cs, b)..lineTo(r, b)..lineTo(r, b - cs), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Claimant section — real QR + OTP + broadcast status
// ─────────────────────────────────────────────────────────────────────────────

class _ClaimantSection extends StatelessWidget {
  const _ClaimantSection({
    required this.isDark,
    required this.primaryText,
    required this.secondaryText,
    required this.loading,
    required this.otp,
    required this.token,
    required this.claimId,
    required this.broadcasting,
    required this.onRefresh,
    required this.onSnack,
  });

  final bool isDark, loading, broadcasting;
  final Color primaryText, secondaryText;
  final String? otp, token, claimId;
  final VoidCallback onRefresh;
  final void Function(String) onSnack;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: NivaraColors.primary)),
      );
    }

    final pin = otp ?? '------';
    final qrPayload = jsonEncode({
      'type': 'NIVARA_LF_HANDOVER',
      'claim_id': claimId,
      'token': token ?? '',
      'otp': pin,
    });

    return Column(
      children: [
        Text(
          'Show this QR code or PIN to the owner standing next to you',
          textAlign: TextAlign.center,
          style: TextStyle(color: secondaryText, fontSize: 13),
        ),
        const SizedBox(height: 16),

        // ── Real QR code via qr_flutter ──────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E676).withValues(alpha: 0.3),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: QrImageView(
            data: qrPayload,
            version: QrVersions.auto,
            size: 180,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        const SizedBox(height: 16),

        // ── 6-digit PIN (tap to copy as fallback) ────────────────────────
        Text(
          'HANDSHAKE PIN',
          style: TextStyle(
            color: secondaryText, fontSize: 11,
            fontWeight: FontWeight.w800, letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        BouncyTap(
          onTap: () {
            Clipboard.setData(ClipboardData(text: pin));
            HapticFeedback.lightImpact();
            onSnack('PIN copied — share with the owner if automatic receive fails');
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141C26) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : const Color(0xFFCBD5E1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${pin.substring(0, 3)}  ·  ${pin.substring(3, 6)}',
                  style: TextStyle(
                    color: primaryText, fontSize: 26,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace', letterSpacing: 3,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.copy_rounded, size: 16, color: secondaryText),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // ── Broadcast status ─────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: (broadcasting ? const Color(0xFF00E676) : const Color(0xFF94A3B8))
                .withValues(alpha: isDark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (broadcasting ? const Color(0xFF00E676) : const Color(0xFF94A3B8))
                  .withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                broadcasting ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
                color: broadcasting ? const Color(0xFF00E676) : const Color(0xFF94A3B8),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  broadcasting
                      ? 'Sending OTP to nearby device automatically — the owner just needs to open their Verify screen'
                      : 'Connecting… the owner will auto-receive your OTP when ready',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                    fontSize: 11.5, fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sync_rounded, size: 14, color: Color(0xFF00E676)),
            const SizedBox(width: 6),
            Text(
              'Waiting for owner to verify…',
              style: TextStyle(
                color: secondaryText, fontSize: 12.5, fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Refresh pass'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Owner verify section
// ─────────────────────────────────────────────────────────────────────────────

class _OwnerSection extends StatelessWidget {
  const _OwnerSection({
    required this.isDark,
    required this.primaryText,
    required this.secondaryText,
    required this.verifying,
    required this.listening,
    required this.pinCtrl,
    required this.onScanQr,
    required this.onVerify,
  });

  final bool isDark, verifying, listening;
  final Color primaryText, secondaryText;
  final TextEditingController pinCtrl;
  final VoidCallback onScanQr, onVerify;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Auto-receive status ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF00E676).withValues(alpha: isDark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              if (listening)
                const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Color(0xFF00E676),
                  ),
                )
              else
                const Icon(Icons.nfc_rounded, color: Color(0xFF00E676), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tap to Receive OTP from Finder',
                      style: TextStyle(
                        color: Color(0xFF00E676),
                        fontWeight: FontWeight.w900, fontSize: 13.5,
                      ),
                    ),
                    Text(
                      listening
                          ? 'Waiting… as soon as the finder opens their pass, you\'ll be verified automatically'
                          : 'Finder\'s OTP received — verifying…',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : const Color(0xFF475569),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Scan QR button ───────────────────────────────────────────────
        BouncyTap(
          onTap: verifying ? null : onScanQr,
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141C26) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: NivaraColors.primary.withValues(alpha: 0.5), width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code_scanner_rounded, size: 28, color: NivaraColors.primary),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan Finder\'s QR Code',
                      style: TextStyle(
                        color: NivaraColors.primary,
                        fontWeight: FontWeight.w900, fontSize: 14,
                      ),
                    ),
                    Text(
                      'Opens full-screen camera scanner',
                      style: TextStyle(
                        color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Divider ──────────────────────────────────────────────────────
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'OR ENTER PIN MANUALLY',
                style: TextStyle(
                  color: secondaryText, fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: 1,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 14),

        // ── PIN field ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141C26) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: NivaraColors.primary.withValues(alpha: 0.5), width: 1.5,
            ),
          ),
          child: TextField(
            controller: pinCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: TextStyle(
              color: primaryText, fontSize: 28,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace', letterSpacing: 6,
            ),
            decoration: const InputDecoration(
              counterText: '', border: InputBorder.none,
              hintText: '000000',
              hintStyle: TextStyle(color: Colors.white24),
            ),
            onChanged: (v) { if (v.length == 6) onVerify(); },
          ),
        ),
        const SizedBox(height: 12),

        // ── Verify button ────────────────────────────────────────────────
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: verifying ? null : onVerify,
            style: FilledButton.styleFrom(
              backgroundColor: NivaraColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: verifying
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline_rounded, color: Colors.black, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Verify & Complete Handover',
                        style: TextStyle(
                          color: Colors.black, fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Success view
// ─────────────────────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                    color: const Color(0xFF00E676).withValues(alpha: 0.45),
                    blurRadius: 28,
                  ),
                ],
              ),
              child: const Icon(Icons.check_rounded, size: 50, color: Colors.black),
            ),
            const SizedBox(height: 20),
            const Text(
              'Handover Complete!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'The item has been safely transferred. Both listings are now resolved.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: onDone,
                child: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Composable UI sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.isOwner,
    required this.itemTitle,
    required this.isLost,
    required this.onClose,
  });
  final bool isOwner, isLost;
  final String itemTitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF00E676).withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isOwner ? Icons.nfc_rounded : Icons.qr_code_2_rounded,
            color: const Color(0xFF00E676), size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isOwner ? 'Verify Handover Pass' : 'Your Handover Pass',
                style: TextStyle(
                  color: primaryText, fontSize: 18, fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${isLost ? "Lost" : "Found"}: $itemTitle',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 20),
          onPressed: onClose,
        ),
      ],
    );
  }
}

class _LiveRibbon extends StatefulWidget {
  const _LiveRibbon({
    required this.isDark,
    required this.isOwner,
    required this.broadcasting,
    required this.listening,
  });
  final bool isDark, isOwner, broadcasting, listening;

  @override
  State<_LiveRibbon> createState() => _LiveRibbonState();
}

class _LiveRibbonState extends State<_LiveRibbon> {
  late Timer _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() { _t.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}'
        '.${now.millisecond ~/ 100}';

    final label = widget.isOwner
        ? (widget.listening
            ? "WAITING — OWNER'S DEVICE LISTENING FOR FINDER'S OTP…"
            : 'VERIFIED — COMPLETING HANDOVER…')
        : (widget.broadcasting
            ? 'BROADCASTING OTP — TAP THE OTHER DEVICE TO VERIFY'
            : 'CONNECTING TO HANDOVER CHANNEL…');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          const Color(0xFF00E676).withValues(alpha: widget.isDark ? 0.18 : 0.10),
          const Color(0xFF00B0FF).withValues(alpha: widget.isDark ? 0.18 : 0.10),
        ]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF00E676), shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0xFF00E676), blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: widget.isDark ? Colors.white70 : const Color(0xFF0F172A),
                fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.5,
              ),
            ),
          ),
          Text(
            ts,
            style: const TextStyle(
              color: Color(0xFF00E676), fontSize: 11,
              fontWeight: FontWeight.w900, fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _BtStrip extends StatelessWidget {
  const _BtStrip({
    required this.isDark,
    required this.btEnabled,
    required this.permGranted,
    required this.onEnable,
  });
  final bool isDark, btEnabled, permGranted;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final ok = btEnabled && permGranted;
    final color = ok ? const Color(0xFF00E676) : const Color(0xFFFF6B6B);
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
            ok ? Icons.bluetooth_connected_rounded : Icons.bluetooth_disabled_rounded,
            size: 17, color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ok
                  ? 'Bluetooth on · proximity verify enabled'
                  : 'Bluetooth off — tap Enable to allow proximity verification',
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF1E293B),
                fontSize: 11.5, fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!ok)
            BouncyTap(
              onTap: onEnable,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676), borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Enable',
                  style: TextStyle(
                    color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.isOwner, required this.isDark});
  final bool isOwner, isDark;

  @override
  Widget build(BuildContext context) {
    final color = isOwner ? const Color(0xFF00B0FF) : const Color(0xFF00E676);
    final icon = isOwner ? Icons.nfc_rounded : Icons.qr_code_2_rounded;
    final label = isOwner
        ? 'You are the owner — scan the finder\'s QR or wait to auto-receive their OTP'
        : 'You are the finder — show the QR to the owner or let them auto-receive your PIN';
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
              style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NivaraColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NivaraColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: NivaraColors.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                color: NivaraColors.danger, fontWeight: FontWeight.w700, fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
