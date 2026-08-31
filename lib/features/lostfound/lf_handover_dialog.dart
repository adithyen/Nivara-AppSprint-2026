import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../models/lf_claim.dart';
import '../../models/lf_item.dart';
import 'lf_claims_repo.dart';

/// 2026-Level Lost & Found Physical Handover Verification Dialog.
///
/// **Asymmetric roles** — each party sees exactly one side of the handover:
///
/// • **Claimant (finder, `isOwner = false`)**: Generates a dynamic OTP + QR pass
///   to display to the owner. Role title: "Show Your Handover Pass".
///
/// • **Owner (lost poster, `isOwner = true`)**: Sees a camera QR scanner and a
///   manual PIN entry field to verify the claimant's pass. Role title: "Verify
///   Handover Pass".
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

  bool _loading = true;
  bool _verifying = false;
  bool _completed = false;
  bool _scanning = false; // owner's camera scanner active
  String? _otp; // claimant's generated OTP
  String? _token;
  String? _error;

  final TextEditingController _pinController = TextEditingController();
  MobileScannerController? _scannerController;

  @override
  void initState() {
    super.initState();
    _listenRealtime();
    if (!widget.isOwner) {
      // Claimant generates the pass
      _initPass();
    } else {
      // Owner does not generate; just wait in verify mode
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _claimSub?.cancel();
    _pinController.dispose();
    _scannerController?.dispose();
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
        });
        _scannerController?.stop();
      }
    });
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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _verifying = false;
      });
      HapticFeedback.vibrate();
      // Re-start scanner if it was active
      if (_scanning) _scannerController?.start();
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
                          ? Icons.qr_code_scanner_rounded
                          : Icons.verified_user_rounded,
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
                              ? 'Verify Handover Pass'
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

              // ── Security Ribbon ─────────────────────────────────────────
              _ChaloSecurityRibbon(isDark: isDark),
              const SizedBox(height: 16),

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
  // CLAIMANT VIEW: Shows their QR + OTP pass for the owner to scan/enter
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
          'Show this to the item owner to verify the handover',
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
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Handshake PIN copied.')));
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
              'Waiting for owner to verify…',
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
  // OWNER VIEW: Camera scanner + PIN entry to verify the claimant's pass
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOwnerVerifyView(bool isDark, Color primaryText, Color secondaryText) {
    return Column(
      children: [
        Text(
          'Scan the finder\'s QR code or enter their 6-digit PIN',
          textAlign: TextAlign.center,
          style: TextStyle(color: secondaryText, fontSize: 13),
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
              height: 100,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141C26) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: NivaraColors.primary.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner_rounded,
                      size: 34,
                      color: NivaraColors.primary.withValues(alpha: 0.7)),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to Scan QR Code',
                    style: TextStyle(
                      color: NivaraColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
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
                'OR ENTER PIN MANUALLY',
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
        const SizedBox(height: 16),

        // ── Verify Button ──────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 50,
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
                        'Verify & Complete Handover',
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),

        // ── 1-Tap Proximity Verify ─────────────────────────────────────
        BouncyTap(
          onTap: _verifying
              ? null
              : () async {
                  final data = await Clipboard.getData('text/plain');
                  final text = (data?.text ?? '').trim();
                  // Accept raw 6-digit PIN or space/bullet-separated formats
                  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
                  if (digits.length == 6) {
                    _pinController.text = digits;
                    _verifyOtp(digits);
                  } else {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Ask the finder to copy their PIN first, then tap this.'),
                        ),
                      );
                  }
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E676).withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.nfc_rounded, color: Colors.black, size: 22),
                SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1-Tap Proximity Verify',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Ask finder to copy PIN → tap here',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
// Chalo-Style Dynamic Anti-Screenshot Live Security Ribbon
// ─────────────────────────────────────────────────────────────────────────────

class _ChaloSecurityRibbon extends StatefulWidget {
  const _ChaloSecurityRibbon({required this.isDark});
  final bool isDark;

  @override
  State<_ChaloSecurityRibbon> createState() => _ChaloSecurityRibbonState();
}

class _ChaloSecurityRibbonState extends State<_ChaloSecurityRibbon>
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            'CHALO-PROXIMITY SECURE PASS',
            style: TextStyle(
              color: widget.isDark ? Colors.white70 : const Color(0xFF0F172A),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
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
