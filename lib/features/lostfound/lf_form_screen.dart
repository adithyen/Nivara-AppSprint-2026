import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../core/constants.dart';
import '../../core/services/location_service.dart';
import '../../core/services/offline_queue_service.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/widgets/connectivity_banner.dart';
import '../../models/enums.dart';
import '../../models/lf_item.dart';
import '../../router.dart';
import 'item_card.dart';
import 'lf_contact.dart';

/// Shared form for reporting a lost OR found item — [itemType] selects which.
/// Mirrors CivicReport's [ReportFormScreen]: category → details → date →
/// location → contact → (reward, lost only) → photos → submit. On success the
/// new row is inserted into `lf_items` and we go straight to the match list so
/// the user immediately sees nearby counterparts.
class LFFormScreen extends StatefulWidget {
  const LFFormScreen({super.key, required this.itemType});

  final LFItemType itemType;

  @override
  State<LFFormScreen> createState() => _LFFormScreenState();
}

class _LFFormScreenState extends State<LFFormScreen> {
  final _location = const LocationService();
  final _picker = ImagePicker();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _rewardCtrl = TextEditingController();

  LFCategory? _category;
  DateTime _eventDate = DateTime.now();
  LFContactMethod _contactMethod = LFContactMethod.phone;
  Position? _pos;
  bool _locating = false;
  final List<XFile> _photos = [];
  bool _submitting = false;

  bool get _isLost => widget.itemType == LFItemType.lost;

  @override
  void initState() {
    super.initState();
    _fetchLocation();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _labelCtrl.dispose();
    _contactCtrl.dispose();
    _rewardCtrl.dispose();
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      helpText: _isLost ? 'When did you lose it?' : 'When did you find it?',
    );
    if (picked != null && mounted) setState(() => _eventDate = picked);
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

  Future<List<String>> _uploadPhotos(String uid) async {
    final urls = <String>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < _photos.length; i++) {
      final bytes = await _photos[i].readAsBytes();
      final path = 'lostfound/$uid/${stamp}_$i.jpg';
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
    if (_titleCtrl.text.trim().isEmpty) {
      _snack('Please give the item a short title.');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      _snack('Please describe the item.');
      return;
    }
    final contactError = lfContactValidate(_contactMethod, _contactCtrl.text);
    if (contactError != null) {
      _snack(contactError);
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

    final reward = int.tryParse(_rewardCtrl.text.trim());
    final item = LFItem(
      id: '',
      userId: uid,
      itemType: widget.itemType,
      category: _category!,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      photoUrls: photoUrls,
      lat: _pos?.latitude ?? kDefaultLat,
      lng: _pos?.longitude ?? kDefaultLng,
      locationLabel: _labelCtrl.text.trim().isEmpty
          ? null
          : _labelCtrl.text.trim(),
      eventDate: _eventDate,
      contactMethod: _contactMethod.wire,
      contactValue: _contactCtrl.text.trim(),
      rewardAmount: _isLost && reward != null && reward > 0 ? reward : null,
    );

    try {
      final row = await supabase
          .from(kTableLfItems)
          .insert(item.toInsertMap())
          .select()
          .single();
      final saved = LFItem.fromMap(row);
      if (!mounted) return;
      _snack(
        '${_isLost ? 'Lost' : 'Found'} item posted'
        '${photoNote ?? ''} — searching for matches…',
      );
      // Straight to the match list for the just-created item.
      context.pushReplacement(Routes.lostFoundMatch, extra: saved);
    } catch (e) {
      // Offline fallback
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
    final accent = _isLost ? NivaraColors.danger : NivaraColors.success;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLost ? 'Report a lost item' : 'Report a found item'),
      ),
      body: WithConnectivityBanner(
        child: AbsorbPointer(
          absorbing: _submitting,
          child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Banner(isLost: _isLost, accent: accent),
            const SizedBox(height: 16),
            const _SectionLabel('1. What kind of item?'),
            const SizedBox(height: 8),
            _LFCategoryGrid(
              selected: _category,
              accent: accent,
              onSelect: (c) => setState(() => _category = c),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('2. Details'),
            const SizedBox(height: 8),
            TextField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Black leather wallet',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: _isLost
                    ? 'Distinguishing marks, contents, anything identifying.'
                    : 'Where exactly, condition, any identifying marks.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel(
              '3. ${_isLost ? 'When did you lose it?' : 'When did you find it?'}',
            ),
            const SizedBox(height: 8),
            _DateCard(date: _eventDate, onTap: _pickDate),
            const SizedBox(height: 20),
            const _SectionLabel('4. Location'),
            const SizedBox(height: 8),
            _LocationCard(
              pos: _pos,
              locating: _locating,
              onRefresh: _fetchLocation,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _labelCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Landmark / area (optional)',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('5. How should people reach you?'),
            const SizedBox(height: 8),
            _ContactSelector(
              method: _contactMethod,
              controller: _contactCtrl,
              onMethodChanged: (m) => setState(() => _contactMethod = m),
            ),
            if (_isLost) ...[
              const SizedBox(height: 20),
              const _SectionLabel('6. Reward (optional)'),
              const SizedBox(height: 8),
              TextField(
                controller: _rewardCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Reward amount',
                  prefixText: '₹ ',
                  prefixIcon: Icon(Icons.card_giftcard),
                ),
              ),
            ],
            const SizedBox(height: 20),
            _SectionLabel('${_isLost ? '7' : '6'}. Photos (optional)'),
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
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(
                _submitting
                    ? 'Posting…'
                    : _isLost
                    ? 'Post lost item'
                    : 'Post found item',
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
        ),
      ),
    );
  }
}


class _Banner extends StatelessWidget {
  const _Banner({required this.isLost, required this.accent});
  final bool isLost;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(isLost ? Icons.search_off : Icons.inventory_2, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isLost
                  ? 'Post what you lost. We\'ll surface nearby found items of the '
                        'same kind so you can reconnect.'
                  : 'Post what you found. We\'ll surface nearby lost reports so '
                        'the owner can claim it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
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

/// Compact 3-column category grid for Lost & Found (mirrors CivicReport's grid,
/// but over [LFCategory] and tinted by the lost/found [accent]).
class _LFCategoryGrid extends StatelessWidget {
  const _LFCategoryGrid({
    required this.selected,
    required this.accent,
    required this.onSelect,
  });

  final LFCategory? selected;
  final Color accent;
  final ValueChanged<LFCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.95,
      children: [
        for (final c in LFCategory.values)
          _LFCategoryTile(
            category: c,
            selected: c == selected,
            accent: accent,
            scheme: scheme,
            onTap: () => onSelect(c),
          ),
      ],
    );
  }
}

class _LFCategoryTile extends StatelessWidget {
  const _LFCategoryTile({
    required this.category,
    required this.selected,
    required this.accent,
    required this.scheme,
    required this.onTap,
  });

  final LFCategory category;
  final bool selected;
  final Color accent;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.12)
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                lfCategoryIcon(category),
                color: selected ? accent : scheme.onSurfaceVariant,
                size: 26,
              ),
              const SizedBox(height: 6),
              Text(
                category.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected ? accent : null,
                  fontWeight: selected ? FontWeight.w600 : null,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
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
    // formatDate lives in core/utils; imported transitively via item_card? No —
    // build a short inline label to avoid an extra import here.
    final label =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.event, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.edit_calendar_outlined),
          ],
        ),
      ),
    );
  }
}

/// Contact picker for the report form: a dropdown of [LFContactMethod] plus a
/// value field whose label/hint/keyboard adapt to the chosen method. The value
/// becomes a one-tap deep link on the viewer's side (see [lf_contact.dart]).
class _ContactSelector extends StatelessWidget {
  const _ContactSelector({
    required this.method,
    required this.controller,
    required this.onMethodChanged,
  });

  final LFContactMethod method;
  final TextEditingController controller;
  final ValueChanged<LFContactMethod> onMethodChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Contact via',
            prefixIcon: Icon(Icons.contact_page_outlined),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<LFContactMethod>(
              value: method,
              isExpanded: true,
              isDense: true,
              onChanged: (m) {
                if (m != null) onMethodChanged(m);
              },
              items: [
                for (final m in LFContactMethod.values)
                  DropdownMenuItem(
                    value: m,
                    child: Row(
                      children: [
                        Icon(
                          lfContactIcon(m),
                          size: 18,
                          color: lfContactColor(m),
                        ),
                        const SizedBox(width: 10),
                        Text(m.label),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          keyboardType: lfContactKeyboard(method),
          decoration: InputDecoration(
            labelText: lfContactFieldLabel(method),
            hintText: lfContactHint(method),
            prefixIcon: Icon(lfContactIcon(method)),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: 14,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Only shown to someone who matches with your item.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ],
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
