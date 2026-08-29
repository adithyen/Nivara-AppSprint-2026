import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';
import '../../core/widgets/connectivity_banner.dart';
import '../../models/enums.dart';
import '../auth/auth_controller.dart';

enum FeedbackCategory {
  bug('Report a Bug', Icons.bug_report_rounded, Color(0xFFFF5252)),
  feature('Suggest Feature', Icons.lightbulb_rounded, Color(0xFFFFB300)),
  contact('Contact Developer', Icons.mail_rounded, Color(0xFF00E676));

  final String label;
  final IconData icon;
  final Color color;
  const FeedbackCategory(this.label, this.icon, this.color);
}

/// 2026-Level Flagship In-App Feedback & Developer Contact Screen.
class FeedbackContactScreen extends ConsumerStatefulWidget {
  const FeedbackContactScreen({super.key});

  @override
  ConsumerState<FeedbackContactScreen> createState() => _FeedbackContactScreenState();
}

class _FeedbackContactScreenState extends ConsumerState<FeedbackContactScreen> {
  FeedbackCategory _category = FeedbackCategory.bug;
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _picker = ImagePicker();

  final List<XFile> _photos = [];
  bool _submitting = false;

  static const String _developerEmail = 'adityenh@gmail.com';
  static const String _appVersion = '1.0.42+42';

  @override
  void initState() {
    super.initState();
    final profile = ref.read(authControllerProvider).asData?.value;
    if (profile?.phone != null && profile!.phone!.isNotEmpty) {
      _contactCtrl.text = profile.phone!;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (x != null && mounted) {
      setState(() => _photos.add(x));
    }
  }

  Future<void> _choosePhotoSource() async {
    if (_photos.length >= 4) {
      _snack('Maximum 4 screenshots/photos allowed.');
      return;
    }
    showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF10161E)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take a Screenshot / Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ).then((src) {
      if (src != null) _pickPhoto(src);
    });
  }

  Future<List<String>> _uploadPhotos(String uid) async {
    final urls = <String>[];
    for (final x in _photos) {
      final bytes = await x.readAsBytes();
      final ext = x.path.split('.').last;
      final path = 'feedback/$uid/${DateTime.now().millisecondsSinceEpoch}_${urls.length}.$ext';
      await supabase.storage.from(kBucketPhotos).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: false),
          );
      final publicUrl = supabase.storage.from(kBucketPhotos).getPublicUrl(path);
      urls.add(publicUrl);
    }
    return urls;
  }

  String _formatEmailBody({
    required String uid,
    required String roleName,
    required String userName,
    required List<String> photoUrls,
  }) {
    final now = DateTime.now().toIso8601String();
    final customContact = _contactCtrl.text.trim();

    final buffer = StringBuffer();
    buffer.writeln('====================================');
    buffer.writeln('     NIVARA CIVIC APP FEEDBACK      ');
    buffer.writeln('====================================');
    buffer.writeln('Category:    ${_category.label}');
    buffer.writeln('App Version: $_appVersion');
    buffer.writeln('Platform:    ${Platform.operatingSystem}');
    buffer.writeln('User Role:   $roleName');
    buffer.writeln('User Name:   $userName');
    buffer.writeln('User UID:    $uid');
    if (customContact.isNotEmpty) {
      buffer.writeln('Contact:     $customContact');
    }
    buffer.writeln('Timestamp:   $now');
    buffer.writeln('------------------------------------');
    buffer.writeln('TITLE:');
    buffer.writeln(_titleCtrl.text.trim());
    buffer.writeln('------------------------------------');
    buffer.writeln('DESCRIPTION & DETAILS:');
    buffer.writeln(_descCtrl.text.trim());
    buffer.writeln('------------------------------------');

    if (photoUrls.isNotEmpty) {
      buffer.writeln('ATTACHED SCREENSHOTS (Cloud URLs):');
      for (var i = 0; i < photoUrls.length; i++) {
        buffer.writeln('  [${i + 1}] ${photoUrls[i]}');
      }
      buffer.writeln('------------------------------------');
    } else if (_photos.isNotEmpty) {
      buffer.writeln('ATTACHED LOCAL SCREENSHOTS: ${_photos.length} item(s)');
      buffer.writeln('------------------------------------');
    }

    buffer.writeln('Sent from Nivara Civic Intelligence Platform');
    buffer.writeln('====================================');
    return buffer.toString();
  }

  Future<void> _sendFeedback() async {
    if (_titleCtrl.text.trim().isEmpty) {
      _snack('Please enter a short title / summary.');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _snack('Please provide description or details.');
      return;
    }

    final profile = ref.read(authControllerProvider).asData?.value;
    final uid = profile?.id ?? 'guest_user';
    final roleName = profile?.role.name.toUpperCase() ?? 'GUEST';
    final userName = profile?.displayName ?? 'Anonymous';

    setState(() => _submitting = true);
    HapticFeedback.mediumImpact();

    List<String> photoUrls = [];
    if (_photos.isNotEmpty) {
      try {
        photoUrls = await _uploadPhotos(uid);
      } catch (e) {
        // Fallback gracefully if storage fails
      }
    }

    final subject = '[Nivara Feedback - ${_category.label}] ${_titleCtrl.text.trim()}';
    final body = _formatEmailBody(
      uid: uid,
      roleName: roleName,
      userName: userName,
      photoUrls: photoUrls,
    );

    final uri = Uri(
      scheme: 'mailto',
      path: _developerEmail,
      queryParameters: {
        'subject': subject,
        'body': body,
      },
    );

    bool launched = false;
    try {
      if (await canLaunchUrl(uri)) {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        launched = await launchUrl(uri);
      }
    } catch (_) {
      launched = false;
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    if (launched) {
      HapticFeedback.heavyImpact();
      _snack('Opening mail app with pre-filled template...');
      Navigator.of(context).pop();
    } else {
      // Fallback: Copy to clipboard and display instructions modal
      await Clipboard.setData(ClipboardData(text: 'To: $_developerEmail\nSubject: $subject\n\n$body'));
      HapticFeedback.vibrate();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.copy_all_rounded, color: NivaraColors.primary),
              SizedBox(width: 8),
              Text('Feedback Copied'),
            ],
          ),
          content: Text(
            'Could not automatically launch your email client.\n\n'
            'The entire template and developer email ($_developerEmail) have been copied to your clipboard.\n\n'
            'Please paste it into your preferred mail app to send.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryText = isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B);
    final cardBg = isDark ? const Color(0xFF10161E) : Colors.white;

    final profile = ref.watch(authControllerProvider).asData?.value;
    final roleLabel = switch (profile?.role) {
      UserRole.worker => 'Field Worker',
      UserRole.admin || UserRole.superadmin => 'Government Official / Admin',
      _ => 'Citizen',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feedback & Contact Dev'),
      ),
      body: WithConnectivityBanner(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            // Header Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E676).withValues(alpha: 0.3),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.mail_lock_rounded, color: Colors.black, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Direct Developer Hotline',
                          style: TextStyle(
                            color: primaryText,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Messages and attached screenshots are dispatched to $_developerEmail',
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Category Selector
            Text(
              'Select Category',
              style: TextStyle(
                color: primaryText,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final cat in FeedbackCategory.values) ...[
                  Expanded(
                    child: BouncyTap(
                      onTap: () => setState(() => _category = cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _category == cat
                              ? cat.color.withValues(alpha: isDark ? 0.22 : 0.14)
                              : cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _category == cat
                                ? cat.color
                                : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                            width: _category == cat ? 1.6 : 1.0,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              cat.icon,
                              size: 20,
                              color: _category == cat ? cat.color : secondaryText,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              cat.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _category == cat ? cat.color : primaryText,
                                fontWeight: _category == cat ? FontWeight.w800 : FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (cat != FeedbackCategory.values.last) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 20),

            // Form Inputs
            Text(
              'Summary / Title *',
              style: TextStyle(
                color: primaryText,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: switch (_category) {
                  FeedbackCategory.bug => 'e.g. Map pin freezes when dragging quickly',
                  FeedbackCategory.feature => 'e.g. Add dark mode widget to home screen',
                  FeedbackCategory.contact => 'e.g. Inquiry regarding civic partnership',
                },
                prefixIcon: Icon(_category.icon, size: 18, color: _category.color),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'Detailed Description *',
              style: TextStyle(
                color: primaryText,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _descCtrl,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: switch (_category) {
                  FeedbackCategory.bug =>
                    'Please describe what happened, steps to reproduce, and what you expected...',
                  FeedbackCategory.feature =>
                    'Please describe your proposed feature and how it benefits citizens / workers...',
                  FeedbackCategory.contact =>
                    'Write your message, question, or inquiry here...',
                },
                alignLabelWithHint: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'Your Contact (Optional)',
              style: TextStyle(
                color: primaryText,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _contactCtrl,
              decoration: InputDecoration(
                hintText: 'Email or phone number for replies',
                prefixIcon: const Icon(Icons.alternate_email_rounded, size: 18),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Screenshots & Attachments Strip
            Row(
              children: [
                Text(
                  'Screenshots / Attachments',
                  style: TextStyle(
                    color: primaryText,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${_photos.length}/4)',
                  style: TextStyle(color: secondaryText, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 84,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _photos.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_photos[i].path),
                              width: 84,
                              height: 84,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 3,
                            right: 3,
                            child: GestureDetector(
                              onTap: () => setState(() => _photos.removeAt(i)),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Color(0xB3000000),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  size: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_photos.length < 4)
                    InkWell(
                      onTap: _choosePhotoSource,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF141C26) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              color: Theme.of(context).colorScheme.primary,
                              size: 24,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Attach',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Diagnostic Telemetry Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141C26) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFF00B0FF)),
                      const SizedBox(width: 6),
                      Text(
                        'Auto-Attached Diagnostic Data',
                        style: TextStyle(
                          color: primaryText,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'App Version: $_appVersion • Role: $roleLabel • OS: ${Platform.operatingSystem}',
                    style: TextStyle(
                      color: secondaryText,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Send CTA Button
            BouncyTap(
              onTap: _submitting ? null : _sendFeedback,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.3),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: _submitting
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.black,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Uploading attachments & opening Gmail...',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send_rounded, color: Colors.black, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Send via Email to adityenh@gmail.com',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 14.5,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
