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
// How proximity "Tap to Verify" works (no clipboard, no BLE advertising):
//
//  Channel name: "handover:{claimId}" (private per-claim Supabase Realtime channel)
//
//  CLAIMANT (isOwner=false):
//   1. Generates OTP via RPC → shows real QrImageView + PIN
//   2. Subscribes to channel + listens for 'request_otp' event from owner
//   3. On receiving request → immediately responds with 'otp' broadcast
//   4. Also proactively broadcasts 'otp' every 4 seconds automatically
//
//  OWNER (isOwner=true):
//   1. Subscribes to channel → listens for 'otp' event from claimant
//   2. On receiving OTP → auto-fills PIN field + calls _verifyOtp instantly
//   3. Owner can also tap "Tap to Receive" to send a 'request_otp' event, prompting
//      the claimant's phone to respond immediately even if claimant is between broadcasts
//   4. Can also scan QR (full-screen page) or type PIN manually
// ─────────────────────────────────────────────────────────────────────────────

const String _kEvtOtp = 'otp';
const String _kEvtRequest = 'request_otp';

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
  // Supabase
  StreamSubscription<LFClaim?>? _claimSub;
  RealtimeChannel? _channel; // single shared channel per dialog
  Timer? _broadcastTimer;

  // BLE (display-only)
  StreamSubscription<BluetoothAdapterState>? _btStateSub;
  bool _btEnabled = false;
  bool _btPermGranted = false;

  // State
  bool _loading = true;
  bool _verifying = false;
  bool _completed = false;
  bool _channelReady = false;    // channel has subscribed successfully
  bool _ownerRequesting = false; // owner tapped "Tap to Receive" and is waiting

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
    _setupChannel(); // both roles share one channel
    if (!widget.isOwner) {
      _initPass();
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _claimSub?.cancel();
    _btStateSub?.cancel();
    _broadcastTimer?.cancel();
    _pinCtrl.dispose();
    // Safe channel cleanup
    final ch = _channel;
    if (ch != null) {
      ch.unsubscribe();
      try { supabase.removeChannel(ch); } catch (_) {}
    }
    super.dispose();
  }

  // ── Supabase: claim status stream ─────────────────────────────────────────

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
    if (mounted) {
      setState(() {
        _completed = true;
        _verifying = false;
        _ownerRequesting = false;
      });
    }
  }

  // ── Supabase: shared realtime channel ─────────────────────────────────────

  /// Both owner and claimant subscribe to the SAME channel.
  /// Events:
  ///   'otp'          → claimant → owner (OTP value)
  ///   'request_otp'  → owner → claimant (ask for OTP)
  void _setupChannel() {
    _channel = supabase.channel(
      _channelName,
      opts: const RealtimeChannelConfig(
        ack: false,
        key: '',
      ),
    );

    _channel!
        .onBroadcast(
          event: _kEvtOtp,
          callback: (payload) {
            // Only owner handles incoming OTP and ONLY when owner explicitly initiated a verification request
            if (!widget.isOwner) return;
            if (!mounted || _verifying || _completed) return;
            final otp = payload['otp'] as String?;
            if (otp != null && RegExp(r'^\d{6}$').hasMatch(otp)) {
              if (_ownerRequesting) {
                HapticFeedback.mediumImpact();
                _pinCtrl.text = otp;
                setState(() => _ownerRequesting = false);
                _verifyOtp(otp);
              }
            }
          },
        )
        .onBroadcast(
          event: _kEvtRequest,
          callback: (payload) {
            // Only claimant handles OTP requests
            if (widget.isOwner) return;
            if (!mounted || _completed) return;
            _broadcastOtpNow(); // Respond with OTP on explicit request
          },
        )
        .subscribe((status, _) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            if (mounted) setState(() => _channelReady = true);
          }
        });
  }

  // ── OTP broadcast helpers ─────────────────────────────────────────────────

  Future<void> _broadcastOtpNow() async {
    final otp = _otp;
    if (otp == null || !_channelReady) return;
    try {
      await _channel?.sendBroadcastMessage(
        event: _kEvtOtp,
        payload: {'otp': otp},
      );
    } catch (_) {}
  }

  // ── Owner: tap to request OTP ─────────────────────────────────────────────

  Future<void> _requestOtpFromFinder({bool silent = false}) async {
    if (_verifying || _completed) return;
    if (!silent) {
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _ownerRequesting = true);
    }

    // Send request_otp event — claimant's phone responds immediately
    try {
      await _channel?.sendBroadcastMessage(
        event: _kEvtRequest,
        payload: {'ts': DateTime.now().millisecondsSinceEpoch},
      );
    } catch (_) {}

    if (!silent) {
      // Auto-reset requesting state after 15s if no OTP arrives
      Future.delayed(const Duration(seconds: 15), () {
        if (mounted && _ownerRequesting && !_completed && !_verifying) {
          setState(() => _ownerRequesting = false);
          _snack("No response. Make sure the finder's Handover Pass is open, then tap again.");
        }
      });
    }
  }

  // ── Bluetooth — display only (permission + on/off badge) ──────────────────

  Future<void> _initBluetooth() async {
    try {
      if (!await FlutterBluePlus.isSupported) return;
      _btStateSub = FlutterBluePlus.adapterState.listen((s) {
        if (mounted) setState(() => _btEnabled = s == BluetoothAdapterState.on);
      });
      final statuses = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      final ok = statuses.values.every((s) => s.isGranted || s.isLimited);
      if (mounted) setState(() => _btPermGranted = ok);
    } catch (_) {}
  }

  // ── Claimant: generate pass ────────────────────────────────────────────────

  Future<void> _initPass() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await LFClaimsRepo.generateHandoverPass(widget.claim.id);
      if (!mounted) return;
      final otp = res['otp'] as String?;
      setState(() {
        _otp = otp;
        _token = res['token'] as String?;
        _loading = false;
      });
      // If channel is already subscribed, broadcast initial status
      if (_channelReady && otp != null) {
        _broadcastOtpNow();
      }
      // If channel is not yet subscribed, the subscribe callback will start broadcasting
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  // ── Verify OTP ─────────────────────────────────────────────────────────────

  Future<void> _verifyOtp(String pin) async {
    final trimmed = pin.trim();
    if (trimmed.length < 6 || _verifying) return;
    setState(() { _verifying = true; _error = null; });
    HapticFeedback.mediumImpact();
    try {
      await LFClaimsRepo.verifyHandover(claimId: widget.claim.id, otp: trimmed);
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

  // ── QR Scanner (full-screen page) ─────────────────────────────────────────

  Future<void> _openQrScanner() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _QRScanPage(),
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      _pinCtrl.text = result;
      _verifyOtp(result);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : const Color(0xFF0F172A);
    final sub = isDark ? Colors.white60 : const Color(0xFF64748B);

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
              _LiveRibbon(
                isDark: isDark,
                isOwner: widget.isOwner,
                channelReady: _channelReady,
                broadcasting: !widget.isOwner && _channelReady && _otp != null,
                requesting: _ownerRequesting,
              ),
              const SizedBox(height: 8),
              _BtStrip(
                isDark: isDark,
                btEnabled: _btEnabled,
                permGranted: _btPermGranted,
              ),
              const SizedBox(height: 12),
              _RoleBadge(isOwner: widget.isOwner, isDark: isDark),
              const SizedBox(height: 14),
              if (_error != null) _ErrorBanner(error: _error!),
              if (widget.isOwner)
                _OwnerSection(
                  isDark: isDark,
                  fg: fg, sub: sub,
                  verifying: _verifying,
                  requesting: _ownerRequesting,
                  pinCtrl: _pinCtrl,
                  onScanQr: _openQrScanner,
                  onTapReceive: _requestOtpFromFinder,
                  onVerify: () => _verifyOtp(_pinCtrl.text),
                )
              else
                _ClaimantSection(
                  isDark: isDark,
                  fg: fg, sub: sub,
                  loading: _loading,
                  otp: _otp,
                  token: _token,
                  claimId: widget.claim.id,
                  channelReady: _channelReady,
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
// Full-screen QR Scanner — fixes BottomSheet black-box issue
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
  String? _debugLast; // last detected raw value (shown briefly for debugging)

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final barcode in cap.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      // Show debug info for 2 seconds so user can see what was detected
      if (mounted) setState(() => _debugLast = 'Detected: ${raw.length > 40 ? '${raw.substring(0, 40)}…' : raw}');

      String? otp;

      // Try JSON payload (new format)
      try {
        final p = jsonDecode(raw) as Map<String, dynamic>;
        if (p['type'] == 'NIVARA_LF_HANDOVER') {
          otp = p['otp']?.toString();
        }
      } catch (_) {}

      // Fallback: raw 6-digit OTP
      if (otp == null || otp.isEmpty) {
        final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length == 6) otp = digits;
      }

      if (otp != null && RegExp(r'^\d{6}$').hasMatch(otp)) {
        _done = true;
        HapticFeedback.heavyImpact();
        Navigator.of(context).pop(otp);
        return;
      }
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
          "Scan Finder's QR Code",
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
          // Instructions
          Positioned(
            bottom: 56, left: 24, right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Point camera at the QR code on the finder's screen",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 13.5),
                  ),
                  if (_debugLast != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _debugLast!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF00E676), fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
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
  Widget build(BuildContext context) => CustomPaint(painter: _ReticlePainter());
}

class _ReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const box = 240.0;
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
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const cs = 32.0;
    canvas.drawPath(Path()..moveTo(l, t + cs)..lineTo(l, t)..lineTo(l + cs, t), p);
    canvas.drawPath(Path()..moveTo(r - cs, t)..lineTo(r, t)..lineTo(r, t + cs), p);
    canvas.drawPath(Path()..moveTo(l, b - cs)..lineTo(l, b)..lineTo(l + cs, b), p);
    canvas.drawPath(Path()..moveTo(r - cs, b)..lineTo(r, b)..lineTo(r, b - cs), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Claimant section
// ─────────────────────────────────────────────────────────────────────────────

class _ClaimantSection extends StatelessWidget {
  const _ClaimantSection({
    required this.isDark,
    required this.fg,
    required this.sub,
    required this.loading,
    required this.otp,
    required this.token,
    required this.claimId,
    required this.channelReady,
    required this.onRefresh,
    required this.onSnack,
  });

  final bool isDark, loading, channelReady;
  final Color fg, sub;
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
      'claim_id': claimId ?? '',
      'token': token ?? '',
      'otp': pin,
    });

    return Column(
      children: [
        Text(
          'Show this QR or PIN to the owner. Your OTP is sent automatically to their device.',
          textAlign: TextAlign.center,
          style: TextStyle(color: sub, fontSize: 13),
        ),
        const SizedBox(height: 16),

        // Real scannable QR code via qr_flutter
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E676).withValues(alpha: 0.3),
                blurRadius: 24, offset: const Offset(0, 6),
              ),
            ],
          ),
          child: QrImageView(
            data: qrPayload,
            version: QrVersions.auto,
            size: 190,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        const SizedBox(height: 16),

        // PIN display (tap to copy)
        Text(
          'HANDSHAKE PIN',
          style: TextStyle(
            color: sub, fontSize: 11,
            fontWeight: FontWeight.w800, letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        BouncyTap(
          onTap: () {
            Clipboard.setData(ClipboardData(text: pin));
            HapticFeedback.lightImpact();
            onSnack('PIN copied');
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
                    color: fg, fontSize: 28,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace', letterSpacing: 3,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.copy_rounded, size: 16, color: sub),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Channel status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: (channelReady
                    ? const Color(0xFF00E676)
                    : const Color(0xFF94A3B8))
                .withValues(alpha: isDark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (channelReady
                      ? const Color(0xFF00E676)
                      : const Color(0xFF94A3B8))
                  .withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              if (!channelReady)
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF94A3B8),
                  ),
                )
              else
                const Icon(Icons.wifi_tethering_rounded,
                    color: Color(0xFF00E676), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  channelReady
                      ? 'Your OTP is broadcasting — owner will auto-receive when they open Verify'
                      : 'Connecting to secure channel…',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                    fontSize: 11.5, fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sync_rounded, size: 14, color: Color(0xFF00E676)),
            const SizedBox(width: 6),
            Text(
              'Waiting for owner to verify…',
              style: TextStyle(
                color: sub, fontSize: 12, fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
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
    required this.fg,
    required this.sub,
    required this.verifying,
    required this.requesting,
    required this.pinCtrl,
    required this.onScanQr,
    required this.onTapReceive,
    required this.onVerify,
  });

  final bool isDark, verifying, requesting;
  final Color fg, sub;
  final TextEditingController pinCtrl;
  final VoidCallback onScanQr, onTapReceive, onVerify;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Tap to receive OTP ───────────────────────────────────────────
        BouncyTap(
          onTap: (verifying || requesting) ? null : onTapReceive,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E676).withValues(alpha: 0.35),
                  blurRadius: 18, offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                if (requesting || verifying)
                  const SizedBox(
                    width: 28, height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.black,
                    ),
                  )
                else
                  const Icon(Icons.nfc_rounded, color: Colors.black, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tap to Receive OTP from Finder',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900, fontSize: 14.5,
                        ),
                      ),
                      Text(
                        requesting
                            ? 'Waiting for finder to respond… keep screens near'
                            : verifying
                                ? 'Verifying received OTP…'
                                : 'Tap this — finder gets a ping & sends OTP automatically',
                        style: const TextStyle(
                          color: Colors.black87, fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Scan QR ──────────────────────────────────────────────────────
        BouncyTap(
          onTap: verifying ? null : onScanQr,
          child: Container(
            height: 60,
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
                Icon(Icons.qr_code_scanner_rounded,
                    size: 26, color: NivaraColors.primary),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Scan Finder's QR Code",
                      style: TextStyle(
                        color: NivaraColors.primary,
                        fontWeight: FontWeight.w900, fontSize: 14,
                      ),
                    ),
                    Text(
                      'Opens full-screen camera · works instantly',
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

        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'OR ENTER PIN MANUALLY',
                style: TextStyle(
                  color: sub, fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: 1,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 12),

        // ── PIN input ────────────────────────────────────────────────────
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
              color: fg, fontSize: 28,
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

        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: verifying ? null : onVerify,
            style: FilledButton.styleFrom(
              backgroundColor: NivaraColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: verifying
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          color: Colors.black, size: 20),
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
// Small composable widgets
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
    final fg = isDark ? Colors.white : const Color(0xFF0F172A);
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
                  color: fg, fontSize: 18, fontWeight: FontWeight.w800,
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
    required this.channelReady,
    required this.broadcasting,
    required this.requesting,
  });
  final bool isDark, isOwner, channelReady, broadcasting, requesting;

  @override
  State<_LiveRibbon> createState() => _LiveRibbonState();
}

class _LiveRibbonState extends State<_LiveRibbon> {
  late final Timer _t;

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
    final ts = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond ~/ 100}';

    String label;
    if (!widget.channelReady) {
      label = 'CONNECTING…';
    } else if (widget.isOwner) {
      label = widget.requesting
          ? 'WAITING FOR FINDER RESPONSE…'
          : 'LISTENING — TAP RECEIVE OR SCAN QR';
    } else {
      label = widget.broadcasting
          ? 'BROADCASTING OTP — OWNER WILL AUTO-RECEIVE'
          : 'CONNECTED — SHOW QR TO OWNER';
    }

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
            decoration: BoxDecoration(
              color: widget.channelReady
                  ? const Color(0xFF00E676)
                  : const Color(0xFFFFB74D),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.channelReady
                      ? const Color(0xFF00E676)
                      : const Color(0xFFFFB74D),
                  blurRadius: 6,
                ),
              ],
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
  });
  final bool isDark, btEnabled, permGranted;

  @override
  Widget build(BuildContext context) {
    final ok = btEnabled && permGranted;
    final color = ok ? const Color(0xFF00E676) : const Color(0xFFFFB74D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.bluetooth_connected_rounded : Icons.bluetooth_rounded,
            size: 16, color: color,
          ),
          const SizedBox(width: 8),
          Text(
            ok
                ? 'Bluetooth on'
                : 'Bluetooth off — OTP sharing still works via internet',
            style: TextStyle(
              color: isDark ? Colors.white60 : const Color(0xFF475569),
              fontSize: 11, fontWeight: FontWeight.w600,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isOwner ? Icons.nfc_rounded : Icons.qr_code_2_rounded,
            color: color, size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isOwner
                  ? "Owner — tap 'Receive OTP' to get finder's code, or scan their QR"
                  : "Finder — your OTP sends to the owner automatically when they tap",
              style: TextStyle(
                color: color, fontSize: 11.5, fontWeight: FontWeight.w700,
              ),
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
          const Icon(Icons.error_outline_rounded,
              color: NivaraColors.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                color: NivaraColors.danger,
                fontWeight: FontWeight.w700, fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
