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
import '../../models/lf_item.dart';
import '../map/location_picker_screen.dart';
import 'item_card.dart';

/// Shared 2-step form for reporting a lost OR found item — [itemType] selects which.
///
/// Flow:
/// 1. Category Selection: User picks category (Electronics, Wallet, Keys, etc.).
/// 2. Details Form: Immediately opens item details with preselected category banner,
///    Ola Map location picker, contact info, photo evidence, and submit.
class LFFormScreen extends StatefulWidget {
  const LFFormScreen({
    super.key,
    required this.itemType,
    this.initialCategory,
  });

  final LFItemType itemType;
  final LFCategory? initialCategory;

  @override
  State<LFFormScreen> createState() => _LFFormScreenState();
}

class _LFFormScreenState extends State<LFFormScreen> {
  final _location = const LocationService();
  final _ola = OlaMapsService.instance;
  final _picker = ImagePicker();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _rewardCtrl = TextEditingController();
  final _categoryFilterCtrl = TextEditingController();

  LFCategory? _category;
  DateTime _eventDate = DateTime.now();
  LFContactMethod _contactMethod = LFContactMethod.phone;
  Position? _pos;
  double? _customLat;
  double? _customLng;
  bool _locating = false;
  final List<XFile> _photos = [];
  bool _submitting = false;

  bool get _isLost => widget.itemType == LFItemType.lost;
  double get _effectiveLat => _customLat ?? _pos?.latitude ?? kDefaultLat;
  double get _effectiveLng => _customLng ?? _pos?.longitude ?? kDefaultLng;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _fetchLocation();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _labelCtrl.dispose();
    _contactCtrl.dispose();
    _rewardCtrl.dispose();
    _categoryFilterCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    setState(() => _locating = true);
    final perm = await _location.ensurePermission();
    Position? pos;
    if (_location.isGranted(perm)) pos = await _location.current();
    if (!mounted) return;
    setState(() {
      _pos = pos;
      _locating = false;
    });

    if (pos != null && _labelCtrl.text.trim().isEmpty) {
      final addr = await _ola.reverseGeocode(
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (addr != null && mounted && _labelCtrl.text.trim().isEmpty) {
        setState(() => _labelCtrl.text = addr);
      }
    }
  }

  Future<void> _pickLocationOnMap() async {
    final result = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLat: _effectiveLat,
          initialLng: _effectiveLng,
          initialAddress: _labelCtrl.text.trim().isNotEmpty
              ? _labelCtrl.text.trim()
              : null,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _customLat = result.lat;
        _customLng = result.lng;
        _labelCtrl.text = result.address;
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
    if (_photos.length >= 4) {
      _snack('Maximum 4 photos.');
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = now.subtract(const Duration(days: 365));
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate,
      firstDate: first,
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _eventDate = picked);
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
      _snack('Please select an item category.');
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      _snack('Please provide a title.');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _snack('Please describe the item.');
      return;
    }
    if (_contactCtrl.text.trim().isEmpty) {
      _snack('Please provide your contact information.');
      return;
    }
    final uid = currentUserId;
    if (uid == null) {
      _snack('Please sign in first.');
      return;
    }

    final reward = _isLost ? int.tryParse(_rewardCtrl.text.trim()) : null;

    setState(() => _submitting = true);
    String? photoNote;
    List<String>? photoUrls;
    if (_photos.isNotEmpty) {
      try {
        photoUrls = await _uploadPhotos(uid);
      } catch (_) {
        photoNote = ' (photos skipped — storage not configured)';
      }
    }

    final item = LFItem(
      id: '',
      userId: uid,
      itemType: widget.itemType,
      category: _category!,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      eventDate: _eventDate,
      lat: _effectiveLat,
      lng: _effectiveLng,
      locationLabel: _labelCtrl.text.trim().isEmpty
          ? null
          : _labelCtrl.text.trim(),
      contactMethod: _contactMethod.wire,
      contactValue: _contactCtrl.text.trim(),
      rewardAmount: reward,
      photoUrls: photoUrls,
      createdAt: DateTime.now(),
    );

    try {
      await supabase.from(kTableLfItems).insert(item.toInsertMap());
      if (!mounted) return;
      Navigator.pop(context, true);
      _snack(
        '${widget.itemType.label} listing published${photoNote ?? ''} — auto-matching enabled.',
      );
    } catch (e) {
      // Offline fallback: save to offline queue with photos in temp storage
      try {
        await OfflineQueueService.enqueueLfItem(
          payload: item.toInsertMap(),
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

  // ── Step 1: Category Selection Screen ─────────────────────────────────────
  Widget _buildCategorySelectionScreen() {
    final accent = _isLost ? NivaraColors.danger : NivaraColors.primary;
    final query = _categoryFilterCtrl.text.trim().toLowerCase();
    final filteredCategories = LFCategory.values.where((c) {
      if (query.isEmpty) return true;
      return c.label.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Select ${widget.itemType.label} Category'),
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
                  hintText: 'Search items (e.g. phone, wallet, keys)…',
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
                        style: const TextStyle(color: Colors.white60),
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
                            // Immediately transition to details form!
                            setState(() => _category = cat);
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF141C26),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.14),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    lfCategoryIcon(cat),
                                    color: accent,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  cat.label,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
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
    final accent = _isLost ? NivaraColors.danger : NivaraColors.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text('Report ${widget.itemType.label} Item'),
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
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        lfCategoryIcon(_category!),
                        color: accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Item Category',
                            style: TextStyle(fontSize: 11, color: Colors.white60),
                          ),
                          Text(
                            _category!.label,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(
                          color: accent.withValues(alpha: 0.5),
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

              const _SectionLabel('1. Item Details'),
              const SizedBox(height: 8),
              TextField(
                controller: _titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  hintText: 'e.g. Black leather wallet',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Description *',
                  hintText: _isLost
                      ? 'Distinguishing marks, contents, anything identifying.'
                      : 'Where exactly, condition, any identifying marks.',
                  alignLabelWithHint: true,
                ),
              ),

              const SizedBox(height: 20),
              _SectionLabel(
                '2. ${_isLost ? 'When did you lose it?' : 'When did you find it?'}',
              ),
              const SizedBox(height: 8),
              _DateCard(date: _eventDate, onTap: _pickDate),

              const SizedBox(height: 20),
              const _SectionLabel('3. Location'),
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
                controller: _labelCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Landmark / place (optional)',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),

              const SizedBox(height: 20),
              const _SectionLabel('4. Contact Info'),
              const SizedBox(height: 8),
              _ContactMethodSelector(
                value: _contactMethod,
                accent: accent,
                onChanged: (m) => setState(() => _contactMethod = m),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contactCtrl,
                keyboardType: _contactMethod == LFContactMethod.phone
                    ? TextInputType.phone
                    : _contactMethod == LFContactMethod.email
                        ? TextInputType.emailAddress
                        : TextInputType.text,
                decoration: InputDecoration(
                  labelText: _contactMethod.label,
                  hintText: _contactMethod == LFContactMethod.phone
                      ? 'e.g. +91 98765 43210'
                      : _contactMethod == LFContactMethod.email
                          ? 'e.g. name@example.com'
                          : 'Your handle or instructions',
                ),
              ),

              if (_isLost) ...[
                const SizedBox(height: 20),
                const _SectionLabel('5. Reward (optional)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _rewardCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Reward amount (₹)',
                    hintText: 'e.g. 500',
                    prefixText: '₹ ',
                  ),
                ),
              ],

              const SizedBox(height: 20),
              _SectionLabel('${_isLost ? 6 : 5}. Photos (optional)'),
              const SizedBox(height: 8),
              _PhotoStrip(
                photos: _photos,
                onAdd: _choosePhotoSource,
                onRemove: (i) => setState(() => _photos.removeAt(i)),
              ),

              const SizedBox(height: 28),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  _submitting
                      ? 'Publishing…'
                      : 'Publish ${widget.itemType.label} item',
                ),
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

class _DateCard extends StatelessWidget {
  const _DateCard({required this.date, required this.onTap});
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: ListTile(
        leading: const Icon(Icons.calendar_today),
        title: Text('$d-$m-$y'),
        subtitle: const Text('Tap to change'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
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

class _ContactMethodSelector extends StatelessWidget {
  const _ContactMethodSelector({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final LFContactMethod value;
  final Color accent;
  final ValueChanged<LFContactMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<LFContactMethod>(
      segments: const [
        ButtonSegment(
          value: LFContactMethod.phone,
          icon: Icon(Icons.phone),
          label: Text('Phone'),
        ),
        ButtonSegment(
          value: LFContactMethod.whatsapp,
          icon: Icon(Icons.message),
          label: Text('WhatsApp'),
        ),
        ButtonSegment(
          value: LFContactMethod.email,
          icon: Icon(Icons.email),
          label: Text('Email'),
        ),
      ],
      selected: {value},
      onSelectionChanged: (set) => onChanged(set.first),
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
          if (photos.length < 4)
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
                      'Add (${photos.length}/4)',
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
