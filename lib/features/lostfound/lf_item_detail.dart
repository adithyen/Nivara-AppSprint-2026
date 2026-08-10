import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/lf_item.dart';
import 'item_card.dart';
import 'lf_contact.dart';

/// Full view of one Lost & Found item — reached by tapping a match result or a
/// hub card. Shows the counterpart's photos (tap to zoom, to verify ownership)
/// and a one-tap contact action via [launchLFContact].
///
/// It renders the passed [item] immediately, then re-fetches the full row by id
/// so photos + contact are present even when the caller only had a partial
/// record (e.g. an older `find_nearby_items` payload).
class LFItemDetailScreen extends StatefulWidget {
  const LFItemDetailScreen({
    super.key,
    required this.item,
    this.distanceMeters,
    this.isMatch = false,
  });

  final LFItem item;
  final double? distanceMeters;

  /// True when opened from the match list (adds an "is this yours?" banner).
  final bool isMatch;

  @override
  State<LFItemDetailScreen> createState() => _LFItemDetailScreenState();
}

class _LFItemDetailScreenState extends State<LFItemDetailScreen> {
  late LFItem _item = widget.item;

  @override
  void initState() {
    super.initState();
    _refreshFull();
  }

  Future<void> _refreshFull() async {
    try {
      final row = await supabase
          .from(kTableLfItems)
          .select()
          .eq('id', widget.item.id)
          .maybeSingle();
      if (row != null && mounted) {
        setState(() => _item = LFItem.fromMap(row));
      }
    } catch (_) {
      /* keep the passed item — it's enough to show something useful */
    }
  }

  Future<void> _contact() async {
    final m = _item.contactMethodEnum;
    final value = _item.contactValue;
    if (value == null || value.trim().isEmpty) return;
    final ok = await launchLFContact(m, value);
    if (!ok && mounted) {
      _snack(
        'Could not open ${m.label}. Contact: ${lfContactDisplay(m, value)}',
      );
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final r = _item;
    final accent = r.isLost ? NivaraColors.danger : NivaraColors.success;
    final title = r.title.trim().isNotEmpty ? r.title.trim() : r.category.label;
    return Scaffold(
      appBar: AppBar(title: Text(r.isLost ? 'Lost item' : 'Found item')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (widget.isMatch) _MatchBanner(isLost: r.isLost, accent: accent),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: accent.withValues(alpha: 0.15),
                child: Icon(lfCategoryIcon(r.category), color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _TypePill(isLost: r.isLost, accent: accent),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PhotoGallery(urls: r.photoUrls ?? const []),
          const SizedBox(height: 16),
          _ContactCard(item: r, onContact: _contact, onCopy: _copyContact),
          if (r.description.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _Section(title: 'Description', child: Text(r.description.trim())),
          ],
          const SizedBox(height: 12),
          _Section(
            title: 'Details',
            child: Column(
              children: [
                _MetaRow('Type', r.isLost ? 'Lost' : 'Found'),
                _MetaRow('Category', r.category.label),
                _MetaRow(
                  r.isLost ? 'Lost on' : 'Found on',
                  formatDate(r.eventDate),
                ),
                if (widget.distanceMeters != null)
                  _MetaRow('Distance', formatDistance(widget.distanceMeters!)),
                if (r.locationLabel != null && r.locationLabel!.isNotEmpty)
                  _MetaRow('Area', r.locationLabel!),
                if (r.rewardAmount != null && r.rewardAmount! > 0)
                  _MetaRow('Reward', '₹${r.rewardAmount}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Location',
            child: Text(
              '${r.lat.toStringAsFixed(5)}, ${r.lng.toStringAsFixed(5)}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyContact() async {
    final value = _item.contactValue;
    if (value == null || value.trim().isEmpty) return;
    final display = lfContactDisplay(_item.contactMethodEnum, value);
    await Clipboard.setData(ClipboardData(text: display));
    if (mounted) _snack('Copied $display');
  }
}

class _MatchBanner extends StatelessWidget {
  const _MatchBanner({required this.isLost, required this.accent});
  final bool isLost;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.compare_arrows, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isLost
                  ? 'Someone reported losing this. Check the photos — if it '
                        'matches what you found, reach out below.'
                  : 'Someone found this nearby. Check the photos to confirm '
                        "it's yours, then contact them below.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.isLost, required this.accent});
  final bool isLost;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isLost ? 'LOST' : 'FOUND',
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
    );
  }
}

/// Horizontal strip of photos; tapping one opens a fullscreen, zoomable viewer.
/// When there are no photos it says so plainly — important when the whole point
/// is verifying ownership by sight.
class _PhotoGallery extends StatelessWidget {
  const _PhotoGallery({required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (urls.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.image_not_supported_outlined, color: scheme.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No photos attached to this report.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Photos',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '· tap to zoom',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => _PhotoViewer(urls: urls, initialIndex: i),
                ),
              ),
              child: Hero(
                tag: 'lf_photo_$i${urls[i]}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _NetImage(url: urls[i], width: 150, height: 150),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NetImage extends StatelessWidget {
  const _NetImage({required this.url, this.width, this.height});
  final String url;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Image.network(
      url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      loadingBuilder: (c, child, progress) => progress == null
          ? child
          : Container(
              width: width,
              height: height,
              color: scheme.surfaceContainerHighest,
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
      errorBuilder: (c, _, _) => Container(
        width: width,
        height: height,
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image, color: scheme.outline),
      ),
    );
  }
}

/// Fullscreen, pinch-to-zoom photo viewer with paging across all [urls].
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.urls, required this.initialIndex});
  final List<String> urls;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${widget.urls.length}',
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => Center(
          child: Hero(
            tag: 'lf_photo_$i${widget.urls[i]}',
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Image.network(
                widget.urls[i],
                fit: BoxFit.contain,
                errorBuilder: (c, _, _) => const Icon(
                  Icons.broken_image,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One-tap contact. Shows the method with a meaningful icon + label and the
/// value, launches the relevant app on tap, and offers a copy fallback.
class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.item,
    required this.onContact,
    required this.onCopy,
  });

  final LFItem item;
  final VoidCallback onContact;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!item.hasContact) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.person_off_outlined, color: scheme.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'The poster did not share a contact method.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final m = item.contactMethodEnum;
    final color = lfContactColor(m);
    final display = lfContactDisplay(m, item.contactValue!);
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onContact,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.18),
                  child: Icon(lfContactIcon(m), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.label,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        display,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to ${lfContactActionLabel(m).toLowerCase()}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  onPressed: onCopy,
                  icon: Icon(Icons.copy, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
