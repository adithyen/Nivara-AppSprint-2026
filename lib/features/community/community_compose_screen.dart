import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../models/community_poll.dart';
import '../../models/community_post.dart';
import '../../models/enums.dart';
import '../auth/auth_controller.dart';
import '../lostfound/lf_contact.dart';
import 'community_tab.dart' show communityTypeColor, communityTypeIcon;

/// Full-screen composer for a Community post, reached from the feed's template
/// buttons (or an author's "Edit"). [type] fixes the template; pass [existing]
/// to edit an already-posted entry (polls are not re-editable — the feed only
/// offers Edit on non-poll posts).
///
/// Fields adapt to the template: every post has a title; General/Job/
/// Announcement add a body; Poll adds 2–5 options; General/Job/Announcement can
/// attach a photo; all can be pinned to a location with a visibility radius (or
/// left city-wide) and carry an optional one-tap contact. On success it pops
/// `true` so the feed reloads.
class CommunityComposeScreen extends ConsumerStatefulWidget {
  const CommunityComposeScreen({super.key, required this.type, this.existing});

  final CommunityPostType type;
  final CommunityPost? existing;

  @override
  ConsumerState<CommunityComposeScreen> createState() =>
      _CommunityComposeScreenState();
}

class _CommunityComposeScreenState
    extends ConsumerState<CommunityComposeScreen> {
  final _location = const LocationService();
  final _picker = ImagePicker();

  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _pollCtrls = <TextEditingController>[];

  bool _locationOn = true;
  Position? _pos;
  bool _locating = false;
  double _radiusKm = 5;

  bool _contactOn = false;
  LFContactMethod _contactMethod = LFContactMethod.phone;

  DateTime? _validUntil;

  final List<XFile> _newPhotos = [];
  List<String> _keptPhotos = [];

  bool _submitting = false;

  CommunityPostType get _type => widget.type;
  bool get _isEdit => widget.existing != null;
  bool get _isPoll => _type == CommunityPostType.poll;
  bool get _isJob => _type == CommunityPostType.job;
  bool get _allowsPhoto => !_isPoll;
  bool get _allowsBody => !_isPoll;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = e.title;
      _bodyCtrl.text = e.body ?? '';
      _labelCtrl.text = e.locationLabel ?? '';
      _locationOn = e.hasLocation;
      _radiusKm = e.visibilityRadiusKm.clamp(1, 50);
      _keptPhotos = [...?e.photoUrls];
      _validUntil = e.validUntil;
      if (e.hasContact) {
        _contactOn = true;
        _contactMethod = e.contactMethodEnum ?? LFContactMethod.phone;
        _contactCtrl.text = e.contactValue ?? '';
      }
      if (e.hasLocation) {
        _pos = Position(
          latitude: e.lat!,
          longitude: e.lng!,
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
      }
    }
    if (_isPoll) {
      _pollCtrls.addAll([TextEditingController(), TextEditingController()]);
    }
    // A fresh located post needs a GPS fix; an edit already has coordinates.
    if (!_isEdit && _locationOn) _fetchLocation();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _labelCtrl.dispose();
    _contactCtrl.dispose();
    for (final c in _pollCtrls) {
      c.dispose();
    }
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

  void _addPollOption() {
    if (_pollCtrls.length >= 5) return;
    setState(() => _pollCtrls.add(TextEditingController()));
  }

  void _removePollOption(int i) {
    if (_pollCtrls.length <= 2) return;
    setState(() {
      _pollCtrls.removeAt(i).dispose();
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (x != null && mounted) setState(() => _newPhotos.add(x));
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

  Future<void> _pickValidUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _validUntil ?? now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Open until',
    );
    if (picked != null && mounted) setState(() => _validUntil = picked);
  }

  Future<List<String>> _uploadNew(String uid) async {
    final urls = <String>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < _newPhotos.length; i++) {
      final bytes = await _newPhotos[i].readAsBytes();
      final path = 'community/$uid/${stamp}_$i.jpg';
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

  List<String> _pollLabels() =>
      _pollCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();

  Future<void> _submit() async {
    final uid = currentUserId;
    if (uid == null) {
      _snack('Please sign in first.');
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      _snack(_isPoll ? 'Enter your poll question.' : 'Enter a title.');
      return;
    }
    if (_isPoll && _pollLabels().length < 2) {
      _snack('A poll needs at least two options.');
      return;
    }
    if (_contactOn) {
      final err = lfContactValidate(_contactMethod, _contactCtrl.text);
      if (err != null) {
        _snack(err);
        return;
      }
    }

    setState(() => _submitting = true);

    String? photoNote;
    List<String> photoUrls = [..._keptPhotos];
    if (_allowsPhoto && _newPhotos.isNotEmpty) {
      try {
        photoUrls.addAll(await _uploadNew(uid));
      } catch (_) {
        photoNote = ' (photo upload skipped — storage not configured)';
      }
    }

    final double? lat = _locationOn ? (_pos?.latitude ?? kDefaultLat) : null;
    final double? lng = _locationOn ? (_pos?.longitude ?? kDefaultLng) : null;
    final label = _labelCtrl.text.trim();
    final contactValue = _contactOn ? _contactCtrl.text.trim() : null;

    final payload = <String, dynamic>{
      'post_type': _type.wire,
      'title': _titleCtrl.text.trim(),
      'body': _allowsBody && _bodyCtrl.text.trim().isNotEmpty
          ? _bodyCtrl.text.trim()
          : null,
      'photo_urls': photoUrls.isEmpty ? null : photoUrls,
      'lat': lat,
      'lng': lng,
      'location_label': label.isEmpty ? null : label,
      'visibility_radius_km': _radiusKm,
      'contact_method': _contactOn ? _contactMethod.wire : null,
      'contact_value': contactValue,
      'valid_until': _isJob ? _validUntil?.toIso8601String() : null,
    };

    try {
      if (_isEdit) {
        await supabase
            .from(kTableCommunityPosts)
            .update(payload)
            .eq('id', widget.existing!.id);
      } else {
        payload['author_id'] = uid;
        payload['author_name'] =
            ref.read(authControllerProvider).asData?.value?.displayName ??
            'Citizen';
        final row = await supabase
            .from(kTableCommunityPosts)
            .insert(payload)
            .select()
            .single();
        final post = CommunityPost.fromMap(row);
        if (_isPoll) {
          final labels = _pollLabels();
          await supabase.from(kTableCommunityPollOptions).insert([
            for (var i = 0; i < labels.length; i++)
              CommunityPollOption(
                id: '',
                postId: post.id,
                label: labels[i],
                position: i,
              ).toInsertMap(),
          ]);
        }
      }
      if (!mounted) return;
      _snack('${_isEdit ? 'Post updated' : 'Posted'}${photoNote ?? ''}.');
      context.pop(true);
    } catch (e) {
      // Offline fallback
      try {
        await OfflineQueueService.enqueueCommunity(payload: payload);
        if (!mounted) return;
        _snack('Saved to Offline Queue (Pending Sync) — will sync when back online.');
        context.pop(true);
      } catch (queueErr) {
        if (!mounted) return;
        setState(() => _submitting = false);
        _snack('Could not save: $e');
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
    final color = communityTypeColor(_type);
    return Scaffold(
      appBar: AppBar(title: Text('${_isEdit ? 'Edit' : 'New'} ${_type.label}')),
      body: WithConnectivityBanner(
        child: AbsorbPointer(
          absorbing: _submitting,
          child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Banner(type: _type, color: color),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _isPoll ? 'Poll question' : 'Title',
                hintText: switch (_type) {
                  CommunityPostType.poll => 'e.g. Should we add a speed bump?',
                  CommunityPostType.job => 'e.g. Need an electrician this week',
                  CommunityPostType.announcement =>
                    'e.g. Ward water supply cut on Sunday',
                  CommunityPostType.general => 'What\'s happening nearby?',
                },
              ),
            ),
            if (_allowsBody) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _bodyCtrl,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _isJob ? 'Details' : 'Say more (optional)',
                  alignLabelWithHint: true,
                  hintText: _isJob
                      ? 'Scope, timing, budget, how to reach you.'
                      : null,
                ),
              ),
            ],
            if (_isPoll) ...[
              const SizedBox(height: 20),
              const _SectionLabel('Options'),
              const SizedBox(height: 8),
              for (var i = 0; i < _pollCtrls.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pollCtrls[i],
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: 'Option ${i + 1}',
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_pollCtrls.length > 2)
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: () => _removePollOption(i),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                    ],
                  ),
                ),
              if (_pollCtrls.length < 5)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addPollOption,
                    icon: const Icon(Icons.add),
                    label: const Text('Add option'),
                  ),
                ),
            ],
            if (_isJob) ...[
              const SizedBox(height: 20),
              const _SectionLabel('Open until (optional)'),
              const SizedBox(height: 8),
              _ValidUntilCard(
                date: _validUntil,
                onPick: _pickValidUntil,
                onClear: () => setState(() => _validUntil = null),
              ),
            ],
            const SizedBox(height: 20),
            _SectionLabel(_allowsPhoto ? 'Reach & location' : 'Location'),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _locationOn,
              onChanged: (v) {
                setState(() => _locationOn = v);
                if (v && _pos == null && !_isEdit) _fetchLocation();
              },
              title: const Text('Limit to a nearby area'),
              subtitle: Text(
                _locationOn
                    ? 'Only shown to people within the radius below'
                    : 'Visible to everyone in the city',
              ),
            ),
            if (_locationOn) ...[
              _LocationRow(
                pos: _pos,
                locating: _locating,
                onRefresh: _fetchLocation,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.social_distance, size: 20),
                  const SizedBox(width: 8),
                  Text('Visible within ${_radiusKm.round()} km'),
                ],
              ),
              Slider(
                value: _radiusKm,
                min: 1,
                max: 50,
                divisions: 49,
                label: '${_radiusKm.round()} km',
                onChanged: (v) => setState(() => _radiusKm = v),
              ),
              TextField(
                controller: _labelCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Landmark / area (optional)',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _contactOn,
              onChanged: (v) => setState(() => _contactOn = v),
              title: const Text('Add a contact'),
              subtitle: const Text('A one-tap way for people to reach you'),
            ),
            if (_contactOn) _contactFields(),
            if (_allowsPhoto) ...[
              const SizedBox(height: 20),
              const _SectionLabel('Photo (optional)'),
              const SizedBox(height: 8),
              _PhotoStrip(
                existing: _keptPhotos,
                newPhotos: _newPhotos,
                onAdd: _choosePhotoSource,
                onRemoveExisting: (i) =>
                    setState(() => _keptPhotos.removeAt(i)),
                onRemoveNew: (i) => setState(() => _newPhotos.removeAt(i)),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: color),
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
                  : Icon(_isEdit ? Icons.save : Icons.send),
              label: Text(
                _submitting
                    ? 'Saving…'
                    : _isEdit
                    ? 'Save changes'
                    : 'Post to community',
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
        ),
      ),
    );
  }

  Widget _contactFields() {
    return Column(
      children: [
        const SizedBox(height: 4),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Contact via',
            prefixIcon: Icon(Icons.contact_page_outlined),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<LFContactMethod>(
              value: _contactMethod,
              isExpanded: true,
              isDense: true,
              onChanged: (m) {
                if (m != null) setState(() => _contactMethod = m);
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
          controller: _contactCtrl,
          keyboardType: lfContactKeyboard(_contactMethod),
          decoration: InputDecoration(
            labelText: lfContactFieldLabel(_contactMethod),
            hintText: lfContactHint(_contactMethod),
            prefixIcon: Icon(lfContactIcon(_contactMethod)),
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.type, required this.color});
  final CommunityPostType type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final blurb = switch (type) {
      CommunityPostType.general =>
        'Share news, a question, or a heads-up with people around you.',
      CommunityPostType.poll =>
        'Ask a question and let neighbours vote. Results update live.',
      CommunityPostType.job =>
        'List work you need done. Add a contact so people can reach you.',
      CommunityPostType.announcement =>
        'Broadcast something people nearby should know.',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(communityTypeIcon(type), color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(blurb, style: Theme.of(context).textTheme.bodySmall),
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

class _ValidUntilCard extends StatelessWidget {
  const _ValidUntilCard({
    required this.date,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? date;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = date == null
        ? 'No end date'
        : '${date!.day.toString().padLeft(2, '0')}/'
              '${date!.month.toString().padLeft(2, '0')}/${date!.year}';
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.event_available, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (date != null)
              IconButton(
                tooltip: 'Clear',
                onPressed: onClear,
                icon: const Icon(Icons.close),
              )
            else
              const Icon(Icons.edit_calendar_outlined),
          ],
        ),
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
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
                ? Text(
                    '${pos!.latitude.toStringAsFixed(5)}, '
                    '${pos!.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
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

/// Horizontal photo strip mixing already-uploaded URLs (edit mode) with newly
/// picked local files; each is individually removable.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.existing,
    required this.newPhotos,
    required this.onAdd,
    required this.onRemoveExisting,
    required this.onRemoveNew,
  });

  final List<String> existing;
  final List<XFile> newPhotos;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemoveExisting;
  final ValueChanged<int> onRemoveNew;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _AddButton(onTap: onAdd),
          for (var i = 0; i < existing.length; i++)
            _Thumb(
              child: Image.network(
                existing[i],
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Colors.black12,
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
              onRemove: () => onRemoveExisting(i),
            ),
          for (var i = 0; i < newPhotos.length; i++)
            _Thumb(
              child: Image.file(
                File(newPhotos[i].path),
                width: 96,
                height: 96,
                fit: BoxFit.cover,
              ),
              onRemove: () => onRemoveNew(i),
            ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.child, required this.onRemove});
  final Widget child;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Stack(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: const CircleAvatar(
                radius: 12,
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, size: 15, color: Colors.white),
              ),
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
