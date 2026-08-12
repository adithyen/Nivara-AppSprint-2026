import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/enums.dart';
import '../../models/report.dart';
import '../admin/status_style.dart';
import '../report/category_grid.dart';
import 'worker_repo.dart';

/// A field worker's view of one assigned report. They read the full context
/// (citizen photos, evidence, location) and advance the task: Start work →
/// Mark resolved, the latter attaching a resolution note and a proof photo.
/// All writes go through the `worker_set_report_status` RPC, which verifies the
/// task is actually assigned to this worker. Pops the updated [Report] back.
class WorkerTaskDetailScreen extends StatefulWidget {
  const WorkerTaskDetailScreen({super.key, required this.report});

  final Report report;

  @override
  State<WorkerTaskDetailScreen> createState() => _WorkerTaskDetailScreenState();
}

class _WorkerTaskDetailScreenState extends State<WorkerTaskDetailScreen> {
  late Report _report = widget.report;
  bool _working = false;

  Future<void> _startWork() async {
    setState(() => _working = true);
    try {
      final updated = await WorkerRepo.workerSetStatus(
        reportId: _report.id,
        status: ReportStatus.inProgress,
      );
      if (!mounted) return;
      setState(() {
        _report = updated;
        _working = false;
      });
      _snack('Work started.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _snack('Could not update: $e');
    }
  }

  Future<void> _resolve() async {
    final result = await showModalBottomSheet<_ResolveResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ResolveSheet(),
    );
    if (result == null) return; // cancelled

    setState(() => _working = true);
    try {
      String? photoUrl;
      if (result.photo != null) {
        photoUrl = await _uploadProof(result.photo!);
      }
      final updated = await WorkerRepo.workerSetStatus(
        reportId: _report.id,
        status: ReportStatus.resolved,
        note: result.note,
        photoUrl: photoUrl,
      );
      if (!mounted) return;
      setState(() {
        _report = updated;
        _working = false;
      });
      _snack('Marked resolved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _snack('Could not resolve: $e');
    }
  }

  /// Uploads a proof photo to Storage and returns its public URL.
  Future<String?> _uploadProof(XFile photo) async {
    try {
      final uid = supabase.auth.currentUser?.id ?? 'worker';
      final bytes = await photo.readAsBytes();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = '$uid/proof_${_report.id}_$stamp.jpg';
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
      return supabase.storage.from(kBucketPhotos).getPublicUrl(path);
    } catch (_) {
      // Best-effort: resolve without the photo if the bucket refuses it.
      return null;
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final scheme = Theme.of(context).colorScheme;
    final title = r.title?.trim().isNotEmpty == true
        ? r.title!.trim()
        : r.category.label;
    return Scaffold(
      appBar: AppBar(title: const Text('Task')),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) context.pop(_report);
        },
        child: AbsorbPointer(
          absorbing: _working,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: severityColor(
                      r.severity,
                    ).withValues(alpha: 0.15),
                    child: Icon(
                      categoryIcon(r.category),
                      color: severityColor(r.severity),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        StatusChip(r.status),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (r.hasEvidence) _EvidenceLine(report: r),
              if (r.photoUrls != null && r.photoUrls!.isNotEmpty) ...[
                _PhotoStrip(urls: r.photoUrls!),
                const SizedBox(height: 8),
              ],
              if (r.description?.trim().isNotEmpty == true) ...[
                _Section(
                  title: 'Reported issue',
                  child: Text(r.description!.trim()),
                ),
                const SizedBox(height: 8),
              ],
              _Section(
                title: 'Details',
                child: Column(
                  children: [
                    _MetaRow('Category', r.category.label),
                    _MetaRow('Severity', r.severity.label),
                    if (r.assignedDepartment != null)
                      _MetaRow('Department', r.assignedDepartment!.label),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _Section(
                title: 'Location',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.address?.trim().isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(r.address!.trim()),
                      ),
                    Text(
                      '${r.lat.toStringAsFixed(5)}, ${r.lng.toStringAsFixed(5)}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _Section(
                title: 'Timeline',
                child: Column(
                  children: [
                    _MetaRow('Reported', formatDateTime(r.createdAt)),
                    if (r.acknowledgedAt != null)
                      _MetaRow(
                        'Acknowledged',
                        formatDateTime(r.acknowledgedAt!),
                      ),
                    if (r.resolvedAt != null)
                      _MetaRow('Resolved', formatDateTime(r.resolvedAt!)),
                  ],
                ),
              ),
              if (r.resolutionNotes?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                _Section(
                  title: 'Your resolution note',
                  child: Text(r.resolutionNotes!.trim()),
                ),
              ],
              if (r.resolutionPhoto?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                _Section(
                  title: 'Proof of work',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      r.resolutionPhoto!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (c, _, _) => Container(
                        height: 160,
                        color: scheme.surfaceContainerHighest,
                        child: Icon(Icons.broken_image, color: scheme.outline),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _ActionBar(
                status: r.status,
                working: _working,
                onStart: _startWork,
                onResolve: _resolve,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Worker actions keyed off the current status. Anything open-but-not-started
/// offers "Start work"; in-progress offers "Mark resolved"; done shows a
/// closing banner.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.status,
    required this.working,
    required this.onStart,
    required this.onResolve,
  });

  final ReportStatus status;
  final bool working;
  final VoidCallback onStart;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    Widget spinnerOr(IconData icon) => working
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          )
        : Icon(icon);

    switch (status) {
      case ReportStatus.submitted:
      case ReportStatus.acknowledged:
        return FilledButton.icon(
          onPressed: working ? null : onStart,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: spinnerOr(Icons.engineering),
          label: const Text('Start work'),
        );
      case ReportStatus.inProgress:
        return FilledButton.icon(
          onPressed: working ? null : onResolve,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: NivaraColors.success,
          ),
          icon: spinnerOr(Icons.check_circle),
          label: const Text('Mark resolved'),
        );
      case ReportStatus.resolved:
      case ReportStatus.closed:
      case ReportStatus.duplicate:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NivaraColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle, color: NivaraColors.success),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Task complete. Thanks for the fix!',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
    }
  }
}

/// Bottom sheet to capture a resolution note + optional proof photo.
class _ResolveSheet extends StatefulWidget {
  const _ResolveSheet();

  @override
  State<_ResolveSheet> createState() => _ResolveSheetState();
}

class _ResolveResult {
  const _ResolveResult(this.note, this.photo);
  final String? note;
  final XFile? photo;
}

class _ResolveSheetState extends State<_ResolveSheet> {
  final _note = TextEditingController();
  XFile? _photo;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1600,
    );
    if (picked != null && mounted) setState(() => _photo = picked);
  }

  void _choosePhoto() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Resolve task',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Add a short note and a proof photo of the completed work.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Resolution note',
              hintText: 'What did you fix?',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          if (_photo == null)
            OutlinedButton.icon(
              onPressed: _choosePhoto,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add proof photo'),
            )
          else
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    _photo!.path,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 64,
                      height: 64,
                      color: scheme.surfaceContainerHighest,
                      child: const Icon(Icons.image),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Proof photo attached')),
                TextButton(
                  onPressed: () => setState(() => _photo = null),
                  child: const Text('Remove'),
                ),
              ],
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.pop(
              context,
              _ResolveResult(_note.text.trim(), _photo),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: NivaraColors.success,
            ),
            icon: const Icon(Icons.check_circle),
            label: const Text('Mark resolved'),
          ),
        ],
      ),
    );
  }
}

class _EvidenceLine extends StatelessWidget {
  const _EvidenceLine({required this.report});
  final Report report;

  @override
  Widget build(BuildContext context) {
    final hash = report.evidenceHash ?? '';
    final short = hash.length > 20
        ? '${hash.substring(0, 10)}…${hash.substring(hash.length - 8)}'
        : hash;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NivaraColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NivaraColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user, color: NivaraColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tamper-proof evidence',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: NivaraColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'SHA-256 · $short',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            urls[i],
            width: 120,
            height: 120,
            fit: BoxFit.cover,
            errorBuilder: (c, _, _) => Container(
              width: 120,
              height: 120,
              color: Theme.of(c).colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.broken_image,
                color: Theme.of(c).colorScheme.outline,
              ),
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
            width: 120,
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
