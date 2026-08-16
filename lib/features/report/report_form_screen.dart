import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../core/constants.dart';
import '../../core/services/location_service.dart';
import '../../core/services/offline_queue_service.dart';
import '../../core/services/ola_maps_service.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/connectivity_banner.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../map/location_picker_screen.dart';
import 'category_grid.dart';

/// Manual CivicReport filing.
///
/// Flow:
/// 1. Category Selection: User picks a category from a modern searchable grid.
/// 2. Details Form: Immediately opens details form with preselected category banner,
///    Ola Map location picker, photo evidence, and submit.
class ReportFormScreen extends StatefulWidget {
  const ReportFormScreen({
    super.key,
    this.initialCategory,
    this.initialLat,
    this.initialLng,
    this.initialAddress,
  });

  /// Preselect a category (e.g. when opened from the category grid on home).
  final ReportCategory? initialCategory;
  final double? initialLat;
  final double? initialLng;
  final String? initialAddress;

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
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
    if (_category == null) {
      return _buildCategorySelectionScreen();
    }
    return _buildDetailsFormScreen();
  }

  // ── Step 1: Dedicated Category Selection Screen ───────────────────────────
  Widget _buildCategorySelectionScreen() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final query = _categoryFilterCtrl.text.trim().toLowerCase();
    final filteredCategories = ReportCategory.values.where((c) {
      if (query.isEmpty) return true;
      return c.label.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Issue Category'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: WithConnectivityBanner(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _categoryFilterCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search categories (e.g. pothole, light, drain)…',
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
                                  cat.label,
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
  Widget _buildDetailsFormScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Details'),
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
                            'Issue Category',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white60
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                          Text(
                            _category!.label,
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
                      label: const Text('Change'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              _SectionLabel('1. Issue Details'),
              const SizedBox(height: 8),
              TextField(
                controller: _titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Title (optional)',
                  hintText: 'e.g. Deep pothole near junction',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  hintText: 'Describe what you see and any hazard it poses.',
                  alignLabelWithHint: true,
                ),
              ),

              const SizedBox(height: 16),
              Text('Severity', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              _SeveritySelector(
                value: _severity,
                onChanged: (s) => setState(() => _severity = s),
              ),

              const SizedBox(height: 20),
              _SectionLabel('2. Location'),
              const SizedBox(height: 8),
              _LocationCard(
                pos: _pos,
                customLat: _customLat,
                customLng: _customLng,
                locating: _locating,
                onRefresh: _fetchLocation,
                onPickOnMap: _pickLocationOnMap,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Landmark / address (optional)',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),

              const SizedBox(height: 20),
              _SectionLabel('3. Photos (optional)'),
              const SizedBox(height: 8),
              _PhotoStrip(
                photos: _photos,
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
                label: Text(_submitting ? 'Submitting…' : 'Submit report'),
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
  const _SeveritySelector({required this.value, required this.onChanged});
  final Severity value;
  final ValueChanged<Severity> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<Severity>(
      segments: Severity.values
          .map((s) => ButtonSegment(value: s, label: Text(s.label)))
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
    required this.onRefresh,
    required this.onPickOnMap,
  });

  final Position? pos;
  final double? customLat;
  final double? customLng;
  final bool locating;
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
                                      ? 'Selected on map'
                                      : 'GPS location captured',
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
                  _hasCustom ? 'Change on map' : 'Select on map',
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
    required this.onAdd,
    required this.onRemove,
  });

  final List<XFile> photos;
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
                      'Add (${photos.length}/3)',
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
