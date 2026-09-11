import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../../core/constants.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/offline_queue_service.dart';
import '../../../core/services/ola_maps_service.dart';
import '../../../core/supabase_client.dart';
import '../../../core/theme.dart';
import '../../../models/enums.dart';
import '../../../models/report.dart';
import '../../auth/auth_controller.dart';
import '../../settings/language_controller.dart';
import '../models/civic_ai_models.dart';
import '../services/civic_ai_classifier_service.dart';

class CivicAiReviewSheet extends ConsumerStatefulWidget {
  final CivicAiCapturePayload payload;
  final VoidCallback onRetake;

  const CivicAiReviewSheet({
    super.key,
    required this.payload,
    required this.onRetake,
  });

  @override
  ConsumerState<CivicAiReviewSheet> createState() => _CivicAiReviewSheetState();
}

class _CivicAiReviewSheetState extends ConsumerState<CivicAiReviewSheet> {
  late ReportCategory _category;
  late Severity _severity;
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  String? _address;
  bool _submitting = false;
  bool _addressLoading = false;
  late bool _isHazardDetected;
  bool _showManualOverride = false;
  double? _resolvedLat;
  double? _resolvedLng;

  @override
  void initState() {
    super.initState();
    final d = widget.payload.detection;
    _isHazardDetected = d.isHazardDetected;
    _category = d.category;
    // Multi-signal safety net: ONLY if a hazard is detected and resolved to OTHER, check title/desc/tags
    if (_isHazardDetected && _category == ReportCategory.other) {
      final resolved = CivicAiClassifierService.resolveCivicCategory(
        title: d.title,
        desc: d.description,
        tags: d.visualEvidenceTags,
      );
      if (resolved != ReportCategory.other) {
        _category = resolved;
      }
    }
    _severity = d.severity;
    _titleCtrl = TextEditingController(text: _isHazardDetected ? d.title : '');
    _descCtrl = TextEditingController(text: _isHazardDetected ? d.description : '');
    _address = widget.payload.address;

    _resolveAddress();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolveAddress() async {
    setState(() => _addressLoading = true);
    try {
      double lat = widget.payload.lat;
      double lng = widget.payload.lng;

      // If payload coordinates are fallback default, try to resolve real device GPS now
      if ((lat == kDefaultLat && lng == kDefaultLng) || _address == null || _address!.isEmpty) {
        final freshPos = await const LocationService().current(timeout: const Duration(seconds: 4));
        if (freshPos != null) {
          lat = freshPos.latitude;
          lng = freshPos.longitude;
        }
      }

      final addr = await OlaMapsService.instance.reverseGeocode(
        lat: lat,
        lng: lng,
      );
      if (mounted) {
        setState(() {
          _resolvedLat = lat;
          _resolvedLng = lng;
          _address = addr;
          _addressLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _addressLoading = false);
    }
  }

  Future<void> _submit1Tap() async {
    setState(() => _submitting = true);
    HapticFeedback.mediumImpact();

    final profile = ref.read(authControllerProvider).asData?.value;
    final uid = profile?.id ?? supabase.auth.currentUser?.id;

    List<String>? photoUrls;
    final file = File(widget.payload.photoPath);

    try {
      if (await file.exists()) {
        final ext = widget.payload.photoPath.split('.').last.toLowerCase();
        final path = '${uid ?? 'anon'}/ai_${DateTime.now().millisecondsSinceEpoch}.$ext';
        final bytes = await file.readAsBytes();

        await supabase.storage.from(kBucketPhotos).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: 'image/$ext', upsert: false),
        );
        photoUrls = [supabase.storage.from(kBucketPhotos).getPublicUrl(path)];
      }
    } catch (e) {
      debugPrint('[CivicAiReviewSheet] Photo upload failed, using offline fallback: $e');
    }

    final effectiveLat = _resolvedLat ?? widget.payload.lat;
    final effectiveLng = _resolvedLng ?? widget.payload.lng;

    final report = Report(
      id: '',
      userId: uid,
      category: _category,
      severity: _severity,
      title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      lat: effectiveLat,
      lng: effectiveLng,
      address: _address,
      source: 'MANUAL',
      photoUrls: photoUrls,
      createdAt: DateTime.now(),
    );

    try {
      await supabase.from(kTableReports).insert(report.toInsertMap());
      if (!mounted) return;
      _onSuccess('⚡ AI Auto-Capture Report filed successfully! +25 Civic XP');
    } catch (e) {
      // Offline fallback: save to offline sync queue
      try {
        await OfflineQueueService.enqueueReport(
          payload: report.toInsertMap(),
          photos: [file],
        );
        if (!mounted) return;
        _onSuccess('Saved to Offline Queue (Pending Sync) — will sync when back online.');
      } catch (queueErr) {
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit: $queueErr')),
        );
      }
    }
  }

  void _onSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop(true);
  }

  void _openFullForm() {
    Navigator.of(context).pop();
    context.push(
      '/report',
      extra: {
        'category': _category,
        'lat': _resolvedLat ?? widget.payload.lat,
        'lng': _resolvedLng ?? widget.payload.lng,
        'address': _address,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'severity': _severity,
        'initialPhoto': XFile(widget.payload.photoPath),
      },
    );
  }

  Widget _buildNoHazardNotice(bool isDark, ColorScheme scheme, bool isMalayalam) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isMalayalam ? 'പൊതു ഇടങ്ങളിലെ പ്രശ്നം കാണുന്നില്ല' : 'Non-Hazard Scene Detected',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.amber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.payload.detection.noHazardReason ??
                (isMalayalam
                    ? 'ഈ ഫോട്ടോയിൽ കുഴികൾ, മാലിന്യക്കൂമ്പാരം, തെരുവ് വിളക്ക് കേടുപാടുകൾ തുടങ്ങിയ മുനിസിപ്പൽ പ്രശ്നങ്ങൾ കാണുന്നില്ല (ഉദാഹരണത്തിന്: ഇൻഡോർ മുറി, ലാപ്‌ടോപ്പ്, ടേബിൾ). ദയവായി യഥാർത്ഥ പൊതുപ്രശ്നത്തിലേക്ക് ക്യാമറ തിരിച്ച് വീണ്ടും എടുക്കുക.'
                    : 'The AI examined this image and did not detect any road damage, open drain, garbage dump, or civic hazard (detected indoor or non-civic scene). Please point your camera directly at an outdoor civic issue.'),
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: scheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final currentLang = ref.watch(languageControllerProvider);
    final isMalayalam = currentLang == AppLanguage.ml;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            // Top Header: AI Detection Banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (_isHazardDetected ? NivaraColors.primary : Colors.amber).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _isHazardDetected ? Icons.auto_awesome_rounded : Icons.search_off_rounded,
                      color: _isHazardDetected ? NivaraColors.primary : Colors.amber,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isHazardDetected
                              ? (isMalayalam ? 'AI ഓട്ടോ-ഡിറ്റക്ഷൻ പൂർത്തിയായി' : 'AI Auto-Capture Verified')
                              : (isMalayalam ? 'സിവിക് തകരാറുകൾ കണ്ടെത്തിയില്ല' : 'No Civic Hazard Detected'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          _isHazardDetected
                              ? '${(widget.payload.detection.confidence * 100).toInt()}% Confidence • ${(widget.payload.detection.isSteady) ? "Steady Lock" : "Quick Snap"}'
                              : (isMalayalam ? 'ഫ്രെയിമിൽ പൊതു തകരാറുകൾ ഇല്ല' : 'Indoor or Non-Hazard Scene'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _isHazardDetected ? NivaraColors.primary : Colors.amber,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: widget.onRetake,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(isMalayalam ? 'വീണ്ടും' : 'Retake'),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.error,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 16),

            // When no hazard is detected, show the prominent explanation notice
            if (!_isHazardDetected)
              _buildNoHazardNotice(isDark, scheme, isMalayalam),

            // If no hazard detected and user hasn't opted for manual override,
            // show the photo preview with prominent RETAKE action and manual option.
            if (!_isHazardDetected && !_showManualOverride) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        children: [
                          Image.file(
                            File(widget.payload.photoPath),
                            width: 84,
                            height: 84,
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.amber,
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMalayalam ? 'ക്യാപ്ചർ ചെയ്ത ഫോട്ടോ' : 'Captured Scene',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isMalayalam
                                ? 'പൊതുപ്രശ്നങ്ങളിലേക്ക് ക്യാമറ തിരിച്ച് വീണ്ടും എടുക്കുക.'
                                : 'Point camera directly at a pothole, open drain, or garbage to auto-verify.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  children: [
                    SizedBox(
                      height: 50,
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onRetake,
                        icon: const Icon(Icons.refresh_rounded, size: 22),
                        label: Text(
                          isMalayalam ? '🔄 വീണ്ടും ഫോട്ടോ എടുക്കുക' : '🔄 Retake Photo',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NivaraColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => setState(() => _showManualOverride = true),
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: Text(
                        isMalayalam
                            ? 'സ്വമേധയാ വിഭാഗം തിരഞ്ഞെടുക്കുക (Manual Override)'
                            : 'Report anyway (Select category manually)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Photo Preview & Category Selector Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Captured Photo Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        children: [
                          Image.file(
                            File(widget.payload.photoPath),
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isHazardDetected ? Icons.verified_rounded : Icons.edit_note_rounded,
                                color: _isHazardDetected ? Colors.greenAccent : Colors.amber,
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Category Selector
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMalayalam ? 'വിഭാഗം:' : 'Category:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Dropdown to pick any of the 19 categories
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: NivaraColors.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<ReportCategory>(
                                value: _category,
                                isExpanded: true,
                                icon: const Icon(Icons.arrow_drop_down_rounded),
                                items: ReportCategory.values.map((cat) {
                                  return DropdownMenuItem(
                                    value: cat,
                                    child: Text(
                                      cat.localizedName(currentLang),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (cat) {
                                  if (cat != null) {
                                    setState(() => _category = cat);
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Severity Selector Pills
                          Row(
                            children: Severity.values.map((sev) {
                              final selected = _severity == sev;
                              Color pillColor;
                              switch (sev) {
                                case Severity.low:
                                  pillColor = Colors.teal;
                                  break;
                                case Severity.medium:
                                  pillColor = Colors.amber.shade700;
                                  break;
                                case Severity.high:
                                  pillColor = Colors.orange.shade800;
                                  break;
                                case Severity.emergency:
                                  pillColor = Colors.redAccent;
                                  break;
                              }

                              return Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() => _severity = sev),
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 4),
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? pillColor.withValues(alpha: 0.25)
                                          : (isDark ? Colors.white10 : Colors.black12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: selected ? pillColor : Colors.transparent,
                                        width: 1.5,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      sev.localizedName(currentLang),
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                                        color: selected ? pillColor : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Form Fields: Title & Description
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: isMalayalam ? 'വിഷയം (Title)' : 'Issue Title',
                        prefixIcon: const Icon(Icons.title_rounded, size: 20),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _descCtrl,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        labelText: isMalayalam ? 'വിവരണം (Description)' : 'Hazard Description',
                        prefixIcon: const Icon(Icons.description_rounded, size: 20),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Location & Evidence Tags
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF131F37) : const Color(0xFFEEF2F6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded, color: Colors.redAccent, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _addressLoading
                                ? Row(
                                    children: const [
                                      SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 1.5),
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Resolving GPS via Ola Maps...',
                                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                                      ),
                                    ],
                                  )
                                : Text(
                                    _address ??
                                        '${(_resolvedLat ?? widget.payload.lat).toStringAsFixed(5)}, ${(_resolvedLng ?? widget.payload.lng).toStringAsFixed(5)}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                        ],
                      ),
                      if (widget.payload.detection.visualEvidenceTags.isNotEmpty && _isHazardDetected) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: widget.payload.detection.visualEvidenceTags.map((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: NivaraColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '#$tag',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: NivaraColors.primary,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Primary Action Buttons: 1-Tap Submit & Full Form Edit
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    SizedBox(
                      height: 50,
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _submit1Tap,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.bolt_rounded, size: 22),
                        label: Text(
                          _submitting
                              ? (isMalayalam ? 'സമർപ്പിക്കുന്നു...' : 'Submitting Report...')
                              : (isMalayalam ? '⚡ 1-ടാപ്പ് റിപ്പോർട്ട് സമർപ്പിക്കുക' : '⚡ 1-Tap Submit Report'),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NivaraColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _submitting ? null : _openFullForm,
                        icon: const Icon(Icons.edit_note_rounded, size: 20),
                        label: Text(
                          isMalayalam ? 'മുഴുവൻ ഫോമിൽ എഡിറ്റ് ചെയ്യുക' : 'Edit in Full Report Form',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
