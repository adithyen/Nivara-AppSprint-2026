import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../core/constants.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/location_service.dart';
import '../../core/services/offline_queue_service.dart';
import '../../core/services/ola_maps_service.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/connectivity_banner.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../map/location_picker_screen.dart';
import '../settings/language_controller.dart';
import '../voice_reporting/models/voice_reporting_models.dart';
import '../voice_reporting/presentation/voice_dictation_button.dart';
import '../voice_reporting/presentation/voice_reporting_sheet.dart';
import 'category_grid.dart';

/// Manual CivicReport filing.
///
/// Flow:
/// 1. Category Selection: User picks a category from a modern searchable grid.
/// 2. Details Form: Immediately opens details form with preselected category banner,
///    Ola Map location picker, photo evidence, and submit.
class ReportFormScreen extends ConsumerStatefulWidget {
  const ReportFormScreen({
    super.key,
    this.initialCategory,
    this.initialLat,
    this.initialLng,
    this.initialAddress,
    this.initialTitle,
    this.initialDesc,
    this.initialSeverity,
    this.initialPhoto,
  });

  /// Preselect a category (e.g. when opened from the category grid on home).
  final ReportCategory? initialCategory;
  final double? initialLat;
  final double? initialLng;
  final String? initialAddress;
  final String? initialTitle;
  final String? initialDesc;
  final Severity? initialSeverity;
  final XFile? initialPhoto;

  @override
  ConsumerState<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends ConsumerState<ReportFormScreen> {
  final _location = const LocationService();
  final _ola = OlaMapsService.instance;
  final _picker = ImagePicker();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _categoryFilterCtrl = TextEditingController();

  ReportCategory? _category;
  Severity _severity = Severity.medium;
  Position? _pos;
  double? _customLat;
  double? _customLng;
  bool _locating = false;
  final List<XFile> _photos = [];
  bool _submitting = false;

  double get _effectiveLat => _customLat ?? _pos?.latitude ?? kDefaultLat;
  double get _effectiveLng => _customLng ?? _pos?.longitude ?? kDefaultLng;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    if (widget.initialLat != null && widget.initialLng != null) {
      _customLat = widget.initialLat;
      _customLng = widget.initialLng;
    }
    if (widget.initialAddress != null && widget.initialAddress!.isNotEmpty) {
      _addressCtrl.text = widget.initialAddress!;
    }
    if (widget.initialTitle != null && widget.initialTitle!.isNotEmpty) {
      _titleCtrl.text = widget.initialTitle!;
    }
    if (widget.initialDesc != null && widget.initialDesc!.isNotEmpty) {
      _descCtrl.text = widget.initialDesc!;
    }
    if (widget.initialSeverity != null) {
      _severity = widget.initialSeverity!;
    }
    if (widget.initialPhoto != null) {
      _photos.add(widget.initialPhoto!);
    }
    _fetchLocation();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    _categoryFilterCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    // If user already pre-selected coordinates on map, prioritize them and reverse geocode if needed!
    if (_customLat != null && _customLng != null) {
      if (_addressCtrl.text.trim().isEmpty) {
        setState(() => _locating = true);
        final addr = await _ola.reverseGeocode(
          lat: _customLat!,
          lng: _customLng!,
        );
        if (mounted) {
          setState(() {
            _locating = false;
            if (addr != null && _addressCtrl.text.trim().isEmpty) {
              _addressCtrl.text = addr;
            }
          });
        }
      }
      return;
    }

    setState(() => _locating = true);
    final perm = await _location.ensurePermission();
    Position? pos;
    if (_location.isGranted(perm)) pos = await _location.current();
    if (!mounted) return;
    setState(() {
      _pos = pos;
      _locating = false;
    });

    if (pos != null && _addressCtrl.text.trim().isEmpty && _customLat == null) {
      final addr = await _ola.reverseGeocode(
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (addr != null && mounted && _addressCtrl.text.trim().isEmpty && _customLat == null) {
        setState(() => _addressCtrl.text = addr);
      }
    }
  }

  Future<void> _pickLocationOnMap() async {
    final result = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLat: _effectiveLat,
          initialLng: _effectiveLng,
          initialAddress: _addressCtrl.text.trim().isNotEmpty
              ? _addressCtrl.text.trim()
              : null,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _customLat = result.lat;
        _customLng = result.lng;
        _addressCtrl.text = result.address;
      });
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (x != null && mounted) setState(() => _photos.add(x));
  }

  Future<void> _choosePhotoSource() async {
    if (_photos.length >= 3) {
      _snack('Maximum 3 photos per report.');
      return;
    }
    showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded, color: NivaraColors.primary),
              title: const Text(
                'AI Auto-Capture Scanner',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Auto-detects potholes, drains & 19 civic issues'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/report/ai-camera', extra: _category);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
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
      final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_${urls.length}.$ext';
      await supabase.storage.from(kBucketPhotos).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: false),
          );
      final publicUrl =
          supabase.storage.from(kBucketPhotos).getPublicUrl(path);
      urls.add(publicUrl);
    }
    return urls;
  }

  Future<void> _submit() async {
    if (_category == null) {
      _snack('Please pick a category.');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _snack('Please describe the issue.');
      return;
    }
    final uid = currentUserId;
    if (uid == null) {
      _snack('Please sign in first.');
      return;
    }

    setState(() => _submitting = true);
    String? photoNote;
    List<String>? photoUrls;
    if (_photos.isNotEmpty) {
      try {
        photoUrls = await _uploadPhotos(uid);
      } catch (_) {
        photoNote = ' (photo upload skipped — storage not configured)';
      }
    }

    final report = Report(
      id: '',
      userId: uid,
      category: _category!,
      severity: _severity,
      title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      lat: _effectiveLat,
      lng: _effectiveLng,
      address: _addressCtrl.text.trim().isEmpty
          ? null
          : _addressCtrl.text.trim(),
      source: 'MANUAL',
      photoUrls: photoUrls,
      createdAt: DateTime.now(),
    );

    try {
      await supabase.from(kTableReports).insert(report.toInsertMap());
      if (!mounted) return;
      Navigator.pop(context, true);
      _snack(
        'Report submitted${photoNote ?? ''} — routed to the municipal queue.',
      );
    } catch (e) {
      // Offline fallback: save to local queue with photos in temp storage
      try {
        await OfflineQueueService.enqueueReport(
          payload: report.toInsertMap(),
          photos: _photos.map((p) => File(p.path)).toList(),
        );
        if (!mounted) return;
        Navigator.pop(context, true);
        _snack('Saved to Offline Queue (Pending Sync) — will sync when back online.');
      } catch (queueErr) {
        if (!mounted) return;
        setState(() => _submitting = false);
        _snack('Could not submit: $e');
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final currentLang = ref.watch(languageControllerProvider);

    if (_category == null) {
      return _buildCategorySelectionScreen(currentLang);
    }
    return _buildDetailsFormScreen(currentLang);
  }

  // ── Step 1: Dedicated Category Selection Screen ───────────────────────────
  Widget _buildCategorySelectionScreen(AppLanguage currentLang) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final query = _categoryFilterCtrl.text.trim().toLowerCase();
    final filteredCategories = ReportCategory.values.where((c) {
      if (query.isEmpty) return true;
      return c.label.toLowerCase().contains(query) ||
          c.localizedName(currentLang).toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          NivaraStrings.tr('select_issue_category', currentLang),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: WithConnectivityBanner(
        child: Column(
          children: [
            // AI Auto-Capture Scanner Hero Banner
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.push('/report/ai-camera'),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0284C7), Color(0xFF0F766E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.28),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentLang == AppLanguage.ml
                                    ? '🤖 AI ഓട്ടോ-ക്യാപ്ചർ സ്കാനർ'
                                    : '🤖 AI Auto-Capture Scanner',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                currentLang == AppLanguage.ml
                                    ? 'കുഴികളും ഡ്രെയിനേജും തനിയെ തിരിച്ചറിഞ്ഞ് 1-ടാപ്പിൽ റിപ്പോർട്ട് ചെയ്യാം'
                                    : 'Auto-detects 19 civic issues & captures evidence with 1-tap submit',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white70,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Voice Reporting Assistant Quick Card
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    showVoiceReportingSheet(
                      context,
                      initialMode: VoiceReportMode.civic,
                      onPayloadReady: (payload) {
                        setState(() {
                          _category = payload.civicCategory ?? ReportCategory.pothole;
                          _titleCtrl.text = payload.title;
                          _descCtrl.text = payload.description;
                          _severity = payload.severity;
                          if (payload.extractedLandmark != null) {
                            _addressCtrl.text = payload.extractedLandmark!;
                          }
                        });
                      },
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1B4B).withValues(alpha: 0.5) : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF818CF8).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF818CF8).withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.mic_rounded,
                            color: Color(0xFF818CF8),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentLang == AppLanguage.ml
                                    ? '🎙️ ശബ്ദത്തിലൂടെ പരാതി നൽകാം'
                                    : '🎙️ Voice Reporting Assistant',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                currentLang == AppLanguage.ml
                                    ? 'മലയാളത്തിലോ ഇംഗ്ലീഷിലോ സംസാരിക്കൂ'
                                    : 'Speak naturally in English, Malayalam, or Hindi',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: Color(0xFF818CF8),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: TextField(
                controller: _categoryFilterCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: NivaraStrings.tr('search_categories_hint', currentLang),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _categoryFilterCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _categoryFilterCtrl.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: filteredCategories.isEmpty
                  ? Center(
                      child: Text(
                        'No category found matching "$query"',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : const Color(0xFF6B7280),
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.92,
                      ),
                      itemCount: filteredCategories.length,
                      itemBuilder: (context, i) {
                        final cat = filteredCategories[i];
                        return InkWell(
                          onTap: () {
                            // Immediately transition to the details form!
                            setState(() => _category = cat);
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF141C26)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : const Color(0xFFE2E8F0),
                              ),
                              boxShadow: isDark
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: NivaraColors.primary.withValues(alpha: 0.14),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    categoryIcon(cat),
                                    color: NivaraColors.primary,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  cat.localizedName(currentLang),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : const Color(0xFF111827),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 2: Details Form Screen ───────────────────────────────────────────
  Widget _buildDetailsFormScreen(AppLanguage currentLang) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          NivaraStrings.tr('report_details', currentLang),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (widget.initialCategory != null) {
              Navigator.of(context).pop();
            } else {
              setState(() => _category = null);
            }
          },
        ),
      ),
      body: WithConnectivityBanner(
        child: AbsorbPointer(
          absorbing: _submitting,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Category Pill Card with Change option
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: NivaraColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: NivaraColors.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: NivaraColors.primary.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        categoryIcon(_category!),
                        color: NivaraColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            NivaraStrings.tr('select_issue_category', currentLang),
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white60
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                          Text(
                            _category!.localizedName(currentLang),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white
                                  : const Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(
                          color: NivaraColors.primary.withValues(alpha: 0.5),
                        ),
                      ),
                      onPressed: () => setState(() => _category = null),
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: Text(NivaraStrings.tr('change', currentLang)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SectionLabel(NivaraStrings.tr('sec_issue_details', currentLang)),
                  VoiceDictationButton(
                    mode: VoiceReportMode.civic,
                    isCompact: true,
                    tooltip: currentLang == AppLanguage.ml ? 'ശബ്ദത്തിൽ പറയൂ' : 'Voice Dictate',
                    onPayloadReceived: (payload) {
                      setState(() {
                        if (payload.title.isNotEmpty) _titleCtrl.text = payload.title;
                        if (payload.description.isNotEmpty) _descCtrl.text = payload.description;
                        if (payload.civicCategory != null) _category = payload.civicCategory!;
                        _severity = payload.severity;
                        if (payload.extractedLandmark != null && _addressCtrl.text.isEmpty) {
                          _addressCtrl.text = payload.extractedLandmark!;
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: NivaraStrings.tr('title_optional', currentLang),
                  hintText: 'e.g. Deep pothole near junction',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: NivaraStrings.tr('description_req', currentLang),
                  hintText: 'Describe what you see and any hazard it poses.',
                  alignLabelWithHint: true,
                ),
              ),

              const SizedBox(height: 16),
              Text(
                NivaraStrings.tr('severity', currentLang),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              _SeveritySelector(
                value: _severity,
                currentLang: currentLang,
                onChanged: (s) => setState(() => _severity = s),
              ),

              const SizedBox(height: 20),
              _SectionLabel(NivaraStrings.tr('sec_location', currentLang)),
              const SizedBox(height: 8),
              _LocationCard(
                pos: _pos,
                customLat: _customLat,
                customLng: _customLng,
                locating: _locating,
                currentLang: currentLang,
                onRefresh: _fetchLocation,
                onPickOnMap: _pickLocationOnMap,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: NivaraStrings.tr('landmark_optional', currentLang),
                  prefixIcon: const Icon(Icons.place_outlined),
                ),
              ),

              const SizedBox(height: 20),
              _SectionLabel(NivaraStrings.tr('sec_photos', currentLang)),
              const SizedBox(height: 8),
              _PhotoStrip(
                photos: _photos,
                currentLang: currentLang,
                onAdd: _choosePhotoSource,
                onRemove: (i) => setState(() => _photos.removeAt(i)),
              ),

              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_submitting
                    ? 'Submitting…'
                    : NivaraStrings.tr('submit_report_short', currentLang)),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _SeveritySelector extends StatelessWidget {
  const _SeveritySelector({
    required this.value,
    required this.currentLang,
    required this.onChanged,
  });

  final Severity value;
  final AppLanguage currentLang;
  final ValueChanged<Severity> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<Severity>(
      segments: Severity.values
          .map((s) => ButtonSegment(
                value: s,
                label: Text(s.localizedName(currentLang)),
              ))
          .toList(),
      selected: {value},
      onSelectionChanged: (set) => onChanged(set.first),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.pos,
    this.customLat,
    this.customLng,
    required this.locating,
    required this.currentLang,
    required this.onRefresh,
    required this.onPickOnMap,
  });

  final Position? pos;
  final double? customLat;
  final double? customLng;
  final bool locating;
  final AppLanguage currentLang;
  final VoidCallback onRefresh;
  final VoidCallback onPickOnMap;

  bool get _hasCustom => customLat != null && customLng != null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lat = customLat ?? pos?.latitude;
    final lng = customLng ?? pos?.longitude;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  _hasCustom ? Icons.edit_location_alt : Icons.my_location,
                  color: _hasCustom ? NivaraColors.primary : scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: locating
                      ? const Text('Acquiring location…')
                      : lat == null
                          ? const Text(
                              'Location unavailable — pick on map or enable GPS.',
                              style: TextStyle(fontSize: 13),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _hasCustom
                                      ? NivaraStrings.tr('select_on_map', currentLang)
                                      : NivaraStrings.tr('gps_captured', currentLang),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: _hasCustom
                                        ? NivaraColors.primary
                                        : null,
                                  ),
                                ),
                                Text(
                                  '${lat.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                ),
                if (locating)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Recalculate GPS location',
                    onPressed: onRefresh,
                  ),
              ],
            ),
            const Divider(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onPickOnMap,
                icon: const Icon(Icons.map, size: 18),
                label: Text(
                  NivaraStrings.tr('select_on_map', currentLang),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.photos,
    required this.currentLang,
    required this.onAdd,
    required this.onRemove,
  });

  final List<XFile> photos;
  final AppLanguage currentLang;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < photos.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(photos[i].path),
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => onRemove(i),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (photos.length < 3)
            InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_a_photo,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${NivaraStrings.tr('add_photos', currentLang)} (${photos.length}/3)',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
