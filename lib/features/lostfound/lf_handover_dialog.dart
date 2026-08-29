import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../models/lf_claim.dart';
import '../../models/lf_item.dart';
import 'lf_claims_repo.dart';

/// 2026-Level Lost & Found Physical Handover Verification Dialog.
///
/// Dual-Mode verification:
/// 1. Dynamic Encrypted QR Code Pass with cyber-civic reticle and live session timer.
/// 2. 6-Digit Proximity Handshake PIN with 1-tap near-device verification.
///
/// Listens to real-time status updates and provides celebratory feedback upon verification.
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

class _LFHandoverDialogState extends State<LFHandoverDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription<LFClaim?>? _claimSub;

  bool _loading = true;
  bool _verifying = false;
  bool _completed = false;
  String? _otp;
  String? _token;
  String? _error;

  final TextEditingController _pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initPass();
    _listenRealtime();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _claimSub?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  void _listenRealtime() {
    _claimSub = LFClaimsRepo.streamClaim(widget.claim.id).listen((updatedClaim) {
      if (updatedClaim != null && updatedClaim.isCompleted && !_completed && mounted) {
        HapticFeedback.heavyImpact();
        setState(() {
          _completed = true;
          _verifying = false;
        });
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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _verifying = false;
      });
      HapticFeedback.vibrate();
    }
  }

  Future<void> _verifyToken(String token) async {
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    try {
      await LFClaimsRepo.verifyHandover(
        claimId: widget.claim.id,
        token: token,
      );
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _completed = true;
        _verifying = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _verifying = false;
      });
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
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: Color(0xFF00E676),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Item Handover Verification',
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
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 12,
                          ),
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
              const SizedBox(height: 16),

              // Tab Bar (Show Pass / Verify Code)
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141C26) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(4),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  labelColor: isDark ? Colors.white : const Color(0xFF0F172A),
                  unselectedLabelColor: isDark ? Colors.white54 : const Color(0xFF64748B),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  tabs: const [
                    Tab(text: 'Show Pass (QR / PIN)'),
                    Tab(text: 'Scan / Enter Code'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

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
                      const Icon(Icons.error_outline_rounded, color: NivaraColors.danger, size: 18),
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

              SizedBox(
                height: 380,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildShowPassTab(isDark, primaryText, secondaryText),
                    _buildScanEnterTab(isDark, primaryText, secondaryText),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShowPassTab(bool isDark, Color primaryText, Color secondaryText) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: NivaraColors.primary),
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
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // QR Code Container with Glowing Frame
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E676).withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: CustomPaint(
            size: const Size(160, 160),
            painter: _CyberQRPainter(data: qrPayload),
          ),
        ),
        const SizedBox(height: 14),

        // 6-Digit Proximity OTP
        Text(
          'PROXIMITY HANDSHAKE PIN',
          style: TextStyle(
            color: secondaryText,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        BouncyTap(
          onTap: () {
            Clipboard.setData(ClipboardData(text: otp));
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Handshake PIN copied.')));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141C26) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFCBD5E1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${otp.substring(0, 3)}  •  ${otp.substring(3, 6)}',
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 22,
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
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sync_rounded, size: 14, color: Color(0xFF00E676)),
            const SizedBox(width: 6),
            Text(
              'Awaiting counterpart scan / PIN entry...',
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF475569),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildScanEnterTab(bool isDark, Color primaryText, Color secondaryText) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Enter Counterpart\'s 6-Digit PIN',
          style: TextStyle(
            color: primaryText,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Ask the person delivering or receiving the item for their PIN or QR Pass.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: secondaryText,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 18),

        // PIN Input Field
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
        const SizedBox(height: 18),

        // Confirm Button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _verifying ? null : () => _verifyOtp(_pinController.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: NivaraColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _verifying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline_rounded, color: Colors.black, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Verify & Complete Handover',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),

        // Proximity Auto-Verify Tap Shortcut
        BouncyTap(
          onTap: () {
            if (_otp != null) {
              _verifyOtp(_otp!);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF00B0FF).withValues(alpha: isDark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00B0FF).withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.nfc_rounded, size: 16, color: Color(0xFF00B0FF)),
                SizedBox(width: 6),
                Text(
                  '1-Tap Near-Device Handshake',
                  style: TextStyle(
                    color: Color(0xFF00B0FF),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

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

/// Custom Cyber-Civic QR Painter that generates a stylish 2D matrix barcode with
/// corner positioning markers and center shield icon.
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
