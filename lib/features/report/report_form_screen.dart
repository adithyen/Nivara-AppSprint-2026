import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../core/constants.dart';
import '../../core/services/location_service.dart';
import '../../core/services/offline_queue_service.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/connectivity_banner.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import 'category_grid.dart';

/// Manual CivicReport filing. Pick a category, add details + severity, confirm
/// the auto-captured GPS location, optionally attach photos, and submit — the
/// row inserts into `reports` (the DB trigger fills location + department).
class ReportFormScreen extends StatefulWidget {
  const ReportFormScreen({super.key, this.initialCategory});

  /// Preselect a category (e.g. when opened from the category grid on home).
  final ReportCategory? initialCategory;

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final _location = const LocationService();
  final _picker = ImagePicker();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  ReportCategory? _category;
  Severity _severity = Severity.medium;
  Position? _pos;
  bool _locating = false;
  final List<XFile> _photos = [];
  bool _submitting = false;

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
    _addressCtrl.dispose();
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
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (x != null && mounted) setState(() => _photos.add(x));
  }

  void _choosePhotoSource() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Uploads chosen photos to Storage. Best-effort: if the bucket isn't set up
  /// the caller catches the error and submits without photos.
  Future<List<String>> _uploadPhotos(String uid) async {
    final urls = <String>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < _photos.length; i++) {
      final bytes = await _photos[i].readAsBytes();
      final path = '$uid/${stamp}_$i.jpg';
      await supabase.storage
          .from(kBucketPhotos)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      urls.add(supabase.storage.from(kBucketPhotos).getPublicUrl(path));
    }
    return urls;
  }

  Future<void> _submit() async {
    final uid = currentUserId;
    if (_category == null) {
      _snack('Please choose a category.');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _snack('Please describe the issue.');
      return;
    }
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
      lat: _pos?.latitude ?? kDefaultLat,
      lng: _pos?.longitude ?? kDefaultLng,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Report an issue')),
      body: WithConnectivityBanner(
        child: AbsorbPointer(
          absorbing: _submitting,
          child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionLabel('1. What is the issue?'),
            const SizedBox(height: 8),
            CategoryGrid(
              selected: _category,
              onSelect: (c) => setState(() => _category = c),
            ),
            const SizedBox(height: 20),
            _SectionLabel('2. Details'),
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
                labelText: 'Description',
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
            _SectionLabel('3. Location'),
            const SizedBox(height: 8),
            _LocationCard(
              pos: _pos,
              locating: _locating,
              onRefresh: _fetchLocation,
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
            _SectionLabel('4. Photos (optional)'),
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
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(_submitting ? 'Submitting…' : 'Submit report'),
            ),
            const SizedBox(height: 12),
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
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );
}

class _SeveritySelector extends StatelessWidget {
  const _SeveritySelector({required this.value, required this.onChanged});

  final Severity value;
  final ValueChanged<Severity> onChanged;

  static const _colors = {
    Severity.low: NivaraColors.success,
    Severity.medium: NivaraColors.accent,
    Severity.high: NivaraColors.danger,
    Severity.emergency: NivaraColors.danger,
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final s in Severity.values)
          ChoiceChip(
            label: Text(s.label),
            selected: s == value,
            selectedColor: (_colors[s] ?? NivaraColors.primary).withValues(
              alpha: 0.18,
            ),
            onSelected: (_) => onChanged(s),
          ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.pos,
    required this.locating,
    required this.onRefresh,
  });

  final Position? pos;
  final bool locating;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            pos != null ? Icons.my_location : Icons.location_searching,
            color: pos != null ? NivaraColors.success : scheme.outline,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: locating
                ? const Text('Getting your location…')
                : pos != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${pos!.latitude.toStringAsFixed(5)}, '
                        '${pos!.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Accuracy ±${pos!.accuracy.toStringAsFixed(0)} m',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  )
                : const Text('Location unavailable — using city default.'),
          ),
          IconButton(
            tooltip: 'Refresh location',
            onPressed: locating ? null : onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
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
          _AddButton(onTap: onAdd),
          for (var i = 0; i < photos.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
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
                      child: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 15, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo, color: scheme.outline),
            const SizedBox(height: 4),
            Text('Add', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
