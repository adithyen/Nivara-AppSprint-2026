import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
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
import '../../../models/lf_item.dart';
import '../../../models/report.dart';
import '../../auth/auth_controller.dart';
import '../../settings/language_controller.dart';
import '../models/voice_reporting_models.dart';
import '../services/voice_intent_parser_service.dart';
import '../services/voice_recognition_service.dart';
import 'voice_visualizer_orb.dart';

/// Entry helper to launch the voice reporting sheet anywhere in Nivara.
Future<void> showVoiceReportingSheet(
  BuildContext context, {
  VoiceReportMode? initialMode,
  CommunityPostType? initialCommunityType,
  Function(VoiceReportPayload)? onPayloadReady,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => VoiceReportingSheet(
      initialMode: initialMode,
      initialCommunityType: initialCommunityType,
      onPayloadReady: onPayloadReady,
    ),
  );
}

/// Comprehensive, glassmorphic Voice Reporting Sheet featuring Emil-motion
/// physics, real-time speech-to-text, and automatic slot extraction across
/// Civic, Lost & Found, and Community reporting workflows.
class VoiceReportingSheet extends ConsumerStatefulWidget {
  final VoiceReportMode? initialMode;
  final CommunityPostType? initialCommunityType;
  final Function(VoiceReportPayload)? onPayloadReady;

  const VoiceReportingSheet({
    super.key,
    this.initialMode,
    this.initialCommunityType,
    this.onPayloadReady,
  });

  @override
  ConsumerState<VoiceReportingSheet> createState() => _VoiceReportingSheetState();
}

class _VoiceReportingSheetState extends ConsumerState<VoiceReportingSheet> {
  late VoiceReportMode _mode;
  late CommunityPostType _selectedCommunityType;
  VoiceLanguage _language = VoiceLanguage.auto;
  VoiceState _voiceState = VoiceState.idle;
  double _soundLevel = 0.0;
  String _liveTranscript = '';
  VoiceReportPayload? _parsedPayload;
  bool _isSubmitting = false;

  Position? _currentPosition;
  String? _currentAddress;
  String? _attachedPhotoPath;

  late TextEditingController _transcriptController;
  late FocusNode _transcriptFocusNode;
  Timer? _debounceTimer;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ?? VoiceReportMode.civic;
    _selectedCommunityType = widget.initialCommunityType ?? CommunityPostType.general;
    _transcriptController = TextEditingController();
    _transcriptFocusNode = FocusNode();

    // Match current app language if possible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appLang = ref.read(languageControllerProvider);
      if (appLang == AppLanguage.ml) {
        _language = VoiceLanguage.ml;
      } else if (appLang == AppLanguage.hi) {
        _language = VoiceLanguage.hi;
      } else {
        _language = VoiceLanguage.auto;
      }
      setState(() {});
      _fetchLocation();
      _startVoiceListening();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _transcriptController.dispose();
    _transcriptFocusNode.dispose();
    ref.read(voiceRecognitionServiceProvider).stopListening();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    try {
      final pos = await const LocationService().current();
      _currentPosition = pos;
      if (pos != null) {
        final addr = await OlaMapsService.instance.reverseGeocode(
          lat: pos.latitude,
          lng: pos.longitude,
        );
        if (mounted) setState(() => _currentAddress = addr);
      }
    } catch (_) {}
  }

  Future<void> _startVoiceListening() async {
    final speechService = ref.read(voiceRecognitionServiceProvider);

    final started = await speechService.startListening(
      language: _language,
      existingText: _transcriptController.text,
      onSoundLevel: (level) {
        if (mounted) setState(() => _soundLevel = level);
      },
      onStateChanged: (state) {
        if (mounted) setState(() => _voiceState = state);
      },
      onResult: (text, isFinal) async {
        if (!mounted) return;
        _liveTranscript = text;

        // Auto-update controller directly so real spoken words appear in the text field immediately
        _transcriptController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        setState(() {});

        if (text.trim().isNotEmpty) {
          final parser = ref.read(voiceIntentParserServiceProvider);
          final payload = await parser.parseTranscript(
            text,
            forcedMode: _mode,
            forcedCommunityType: _mode == VoiceReportMode.community ? _selectedCommunityType : null,
            language: _language,
            enableAiRefinement: isFinal,
          );
          if (mounted) {
            setState(() {
              _parsedPayload = payload;
              if (payload.mode != _mode && widget.initialMode == null) {
                _mode = payload.mode;
              }
              if (_mode == VoiceReportMode.community) {
                _selectedCommunityType = payload.communityType;
              }
            });
          }
        } else {
          if (mounted) setState(() => _parsedPayload = null);
        }
      },
    );

    if (!started && mounted) {
      setState(() => _voiceState = VoiceState.idle);
    }
  }

  void _onTranscriptChanged(String val) {
    _liveTranscript = val;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (val.trim().isNotEmpty) {
        final parser = ref.read(voiceIntentParserServiceProvider);
        final payload = await parser.parseTranscript(
          val,
          forcedMode: _mode,
          forcedCommunityType: _mode == VoiceReportMode.community ? _selectedCommunityType : null,
          language: _language,
          enableAiRefinement: false,
        );
        if (mounted) {
          setState(() {
            _parsedPayload = payload;
            if (payload.mode != _mode && widget.initialMode == null) {
              _mode = payload.mode;
            }
            if (_mode == VoiceReportMode.community) {
              _selectedCommunityType = payload.communityType;
            }
          });
        }
      } else {
        if (mounted) setState(() => _parsedPayload = null);
      }
    });
  }

  Future<void> _toggleListening() async {
    final speechService = ref.read(voiceRecognitionServiceProvider);
    HapticFeedback.selectionClick();

    if (_voiceState == VoiceState.listening) {
      await speechService.stopListening();
      setState(() => _voiceState = VoiceState.completed);
    } else {
      await _startVoiceListening();
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked != null && mounted) {
        setState(() => _attachedPhotoPath = picked.path);
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      debugPrint('[VoiceReportingSheet] Photo pick error: $e');
    }
  }

  Future<void> _submit1Tap() async {
    final text = _transcriptController.text.trim();
    if (text.isEmpty) return;

    if (_parsedPayload == null) {
      final parser = ref.read(voiceIntentParserServiceProvider);
      _parsedPayload = await parser.parseTranscript(
        text,
        forcedMode: _mode,
        forcedCommunityType: _mode == VoiceReportMode.community ? _selectedCommunityType : null,
        language: _language,
        enableAiRefinement: false,
      );
    }

    // Photo proof verification for Civic hazard reports
    if (_mode == VoiceReportMode.civic && _attachedPhotoPath == null) {
      final proceed = await _showPhotoProofPrompt();
      if (proceed != true) return;
    }

    await _executeSubmit();
  }

  Future<bool?> _showPhotoProofPrompt() {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final scheme = Theme.of(ctx).colorScheme;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: Colors.amber.withValues(alpha: 0.3),
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_a_photo_rounded, color: Colors.amber, size: 32),
              ),
              const SizedBox(height: 14),
              Text(
                'Photo Proof Required',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Civic hazard reports require photo evidence so municipal field teams can verify and dispatch workers accurately. Would you like to take a photo proof now?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Submit Without Photo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop(false);
                        await _pickPhoto(ImageSource.camera);
                        if (_attachedPhotoPath != null) {
                          _executeSubmit();
                        }
                      },
                      icon: const Icon(Icons.camera_alt_rounded, size: 18),
                      label: const Text('Take Photo Proof'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NivaraColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _executeSubmit() async {
    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    final profile = ref.read(authControllerProvider).asData?.value;
    final uid = profile?.id ?? supabase.auth.currentUser?.id;

    List<String>? photoUrls;
    if (_attachedPhotoPath != null) {
      final file = File(_attachedPhotoPath!);
      if (await file.exists()) {
        final ext = _attachedPhotoPath!.split('.').last.toLowerCase();
        final path = '${uid ?? 'anon'}/voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
        final bytes = await file.readAsBytes();

        try {
          await supabase.storage.from(kBucketPhotos).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
          final publicUrl = supabase.storage.from(kBucketPhotos).getPublicUrl(path);
          photoUrls = [publicUrl];
        } catch (e) {
          debugPrint('[VoiceReportingSheet] Storage upload error: $e');
        }
      }
    }

    try {
      switch (_mode) {
        case VoiceReportMode.civic:
          final report = Report(
            id: '',
            userId: uid,
            category: _parsedPayload!.civicCategory ?? ReportCategory.pothole,
            severity: _parsedPayload!.severity,
            title: _parsedPayload!.title,
            description: _parsedPayload!.description,
            photoUrls: photoUrls,
            lat: _currentPosition?.latitude ?? kDefaultLat,
            lng: _currentPosition?.longitude ?? kDefaultLng,
            address: _parsedPayload!.extractedLandmark ?? _currentAddress,
            source: 'VOICE',
            createdAt: DateTime.now(),
          );
          try {
            await supabase.from(kTableReports).insert(report.toInsertMap());
          } catch (_) {
            await OfflineQueueService.enqueueReport(payload: report.toInsertMap());
          }
          break;

        case VoiceReportMode.lostFound:
          final item = LFItem(
            id: '',
            userId: uid ?? 'anon',
            itemType: _parsedPayload!.lfItemType,
            category: _parsedPayload!.lfCategory ?? LFCategory.other,
            title: _parsedPayload!.title,
            description: _parsedPayload!.description,
            photoUrls: photoUrls,
            eventDate: DateTime.now(),
            locationLabel: _parsedPayload!.extractedLandmark ?? _currentAddress,
            lat: _currentPosition?.latitude ?? kDefaultLat,
            lng: _currentPosition?.longitude ?? kDefaultLng,
            createdAt: DateTime.now(),
          );
          await supabase.from(kTableLfItems).insert(item.toInsertMap());
          break;

        case VoiceReportMode.community:
          final postMap = {
            'user_id': uid,
            'post_type': _selectedCommunityType.wire,
            'title': _parsedPayload?.title ?? _liveTranscript,
            'body': _parsedPayload?.description ?? _liveTranscript,
            if (photoUrls != null && photoUrls.isNotEmpty) 'photo_urls': photoUrls,
            'lat': _currentPosition?.latitude ?? kDefaultLat,
            'lng': _currentPosition?.longitude ?? kDefaultLng,
            'location_label': _parsedPayload?.extractedLandmark ?? _currentAddress,
            'created_at': DateTime.now().toIso8601String(),
          };
          await supabase.from(kTableCommunityPosts).insert(postMap);
          break;
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text('⚡ Spoken ${_mode.label} submitted successfully! +20 Civic XP'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submission error: $e')),
      );
    }
  }

  void _openInFullForm() {
    if (_parsedPayload == null && _liveTranscript.trim().isEmpty) return;
    Navigator.of(context).pop();

    if (widget.onPayloadReady != null && _parsedPayload != null) {
      widget.onPayloadReady!(_parsedPayload!);
      return;
    }

    switch (_mode) {
      case VoiceReportMode.civic:
        context.push(
          '/report',
          extra: {
            'category': _parsedPayload?.civicCategory,
            'title': _parsedPayload?.title ?? _liveTranscript,
            'description': _parsedPayload?.description ?? _liveTranscript,
            'severity': _parsedPayload?.severity ?? Severity.medium,
            'address': _parsedPayload?.extractedLandmark ?? _currentAddress,
            'lat': _currentPosition?.latitude ?? kDefaultLat,
            'lng': _currentPosition?.longitude ?? kDefaultLng,
            if (_attachedPhotoPath != null) 'photoPath': _attachedPhotoPath,
            if (_attachedPhotoPath != null) 'initialPhoto': XFile(_attachedPhotoPath!),
          },
        );
        break;

      case VoiceReportMode.lostFound:
        if ((_parsedPayload?.lfItemType ?? LFItemType.lost) == LFItemType.lost) {
          context.push('/lostfound/lost');
        } else {
          context.push('/lostfound/found');
        }
        break;

      case VoiceReportMode.community:
        context.push(
          '/community/compose',
          extra: {
            'type': _selectedCommunityType,
            'title': _parsedPayload?.title ?? _liveTranscript,
            'body': _parsedPayload?.description ?? _liveTranscript,
            'description': _parsedPayload?.description ?? _liveTranscript,
            'address': _parsedPayload?.extractedLandmark ?? _currentAddress,
          },
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 30,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Handle
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Top Header: Title & Language Pill Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: NivaraColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.mic_none_rounded,
                        color: NivaraColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'AI Voice Assistant',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
                // Language pills
                Row(
                  children: VoiceLanguage.values.map((lang) {
                    final selected = _language == lang;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _language = lang);
                        _startVoiceListening();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: selected
                              ? NivaraColors.primary.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? NivaraColors.primary : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          '${lang.flag} ${lang.label}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                            color: selected ? NivaraColors.primary : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Mode Selector Bar (Civic / Lost & Found / Community)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: VoiceReportMode.values.map((mode) {
                  final selected = _mode == mode;
                  IconData icon;
                  switch (mode) {
                    case VoiceReportMode.civic:
                      icon = Icons.warning_amber_rounded;
                      break;
                    case VoiceReportMode.lostFound:
                      icon = Icons.search_rounded;
                      break;
                    case VoiceReportMode.community:
                      icon = Icons.forum_rounded;
                      break;
                  }

                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _mode = mode;
                          if (_liveTranscript.isNotEmpty) {
                            ref
                                .read(voiceIntentParserServiceProvider)
                                .parseTranscript(
                                  _liveTranscript,
                                  forcedMode: mode,
                                  forcedCommunityType: mode == VoiceReportMode.community ? _selectedCommunityType : null,
                                  language: _language,
                                )
                                .then((p) => setState(() => _parsedPayload = p));
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 6,
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              icon,
                              size: 15,
                              color: selected ? NivaraColors.primary : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              mode.label,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 16),

            // Community Post Category Selector Prompt Card (When Community Mode is active)
            if (_mode == VoiceReportMode.community)
              _buildCommunityCategoryPrompt(isDark, scheme),

            // Pulsing Voice Orb & Sound Visualizer
            Center(
              child: VoiceVisualizerOrb(
                state: _voiceState,
                soundLevel: _soundLevel,
                onTap: _toggleListening,
              ),
            ),

            const SizedBox(height: 8),

            // Status Caption
            Center(
              child: Text(
                _getStatusCaption(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _voiceState == VoiceState.listening
                      ? const Color(0xFF00FFCC)
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Live Editable Transcript Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131F37) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _transcriptFocusNode.hasFocus
                      ? NivaraColors.primary
                      : (isDark ? Colors.white12 : Colors.black12),
                  width: _transcriptFocusNode.hasFocus ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.edit_note_rounded,
                            size: 16,
                            color: NivaraColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Spoken Transcript (Editable)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (_voiceState == VoiceState.listening) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00FFCC).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF00FFCC).withValues(alpha: 0.5)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF00FFCC),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'REC',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF00FFCC),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_transcriptController.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _transcriptController.clear();
                            _liveTranscript = '';
                            _debounceTimer?.cancel();
                            setState(() {
                              _parsedPayload = null;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.clear_rounded, size: 13, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  'Clear',
                                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _transcriptController,
                    focusNode: _transcriptFocusNode,
                    maxLines: 4,
                    minLines: 2,
                    textInputAction: TextInputAction.done,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: _getTranscriptHint(),
                      hintStyle: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                        height: 1.4,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: _onTranscriptChanged,
                  ),
                ],
              ),
            ),

            // Parsed Slots Preview Card
            if (_parsedPayload != null && _liveTranscript.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: NivaraColors.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          size: 16,
                          color: NivaraColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Parsed Slots (${_mode.label})',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: NivaraColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _parsedPayload!.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (_mode == VoiceReportMode.civic && _parsedPayload!.civicCategory != null)
                          _buildSlotChip(
                            label: _parsedPayload!.civicCategory!.label,
                            color: Colors.teal,
                          ),
                        if (_mode == VoiceReportMode.civic)
                          _buildSlotChip(
                            label: _parsedPayload!.severity.label,
                            color: _parsedPayload!.severity == Severity.emergency
                                ? Colors.redAccent
                                : Colors.amber.shade800,
                          ),
                        if (_mode == VoiceReportMode.lostFound) ...[
                          _buildSlotChip(
                            label: _parsedPayload!.lfItemType == LFItemType.lost ? 'LOST' : 'FOUND',
                            color: _parsedPayload!.lfItemType == LFItemType.lost
                                ? Colors.redAccent
                                : Colors.green,
                          ),
                          if (_parsedPayload!.lfCategory != null)
                            _buildSlotChip(
                              label: _parsedPayload!.lfCategory!.label,
                              color: Colors.indigo,
                            ),
                        ],
                        if (_mode == VoiceReportMode.community)
                          _buildSlotChip(
                            label: _parsedPayload!.communityType.label,
                            color: Colors.purple,
                          ),
                        if (_parsedPayload!.extractedLandmark != null)
                          _buildSlotChip(
                            label: '📍 ${_parsedPayload!.extractedLandmark!}',
                            color: Colors.blueGrey,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Photo Proof Evidence Section
            _buildPhotoProofSection(isDark, scheme),

            const SizedBox(height: 18),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openInFullForm,
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text('Open in Form'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: (_isSubmitting || _liveTranscript.trim().isEmpty)
                        ? null
                        : _submit1Tap,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.bolt_rounded, size: 20),
                    label: Text(
                      _isSubmitting ? 'Submitting...' : '⚡ 1-Tap Submit',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NivaraColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildCommunityCategoryPrompt(bool isDark, ColorScheme scheme) {
    final categories = [
      (CommunityPostType.announcement, Icons.campaign_rounded, 'Announcement', 'അറിയിപ്പ്', const Color(0xFF00FFCC)),
      (CommunityPostType.poll, Icons.poll_rounded, 'Poll', 'പോൾ', const Color(0xFFFFB703)),
      (CommunityPostType.job, Icons.work_rounded, 'Job / Service', 'ജോലി/സേവനം', const Color(0xFF00B4D8)),
      (CommunityPostType.general, Icons.forum_rounded, 'General Post', 'പൊതു പോസ്റ്റ്', NivaraColors.primary),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131F37) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: NivaraColors.primary.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: NivaraColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.help_outline_rounded, size: 14, color: NivaraColors.primary),
              ),
              const SizedBox(width: 8),
              Text(
                'Which category of community post?',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Select below or speak your category (Announcement, Poll, Job, General):',
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: categories.map((cat) {
              final isSelected = _selectedCommunityType == cat.$1;
              final color = cat.$5;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedCommunityType = cat.$1;
                    if (_liveTranscript.isNotEmpty) {
                      ref.read(voiceIntentParserServiceProvider).parseTranscript(
                        _liveTranscript,
                        forcedMode: VoiceReportMode.community,
                        forcedCommunityType: cat.$1,
                        language: _language,
                      ).then((p) {
                        if (mounted) setState(() => _parsedPayload = p);
                      });
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: isDark ? 0.25 : 0.15)
                        : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? color : (isDark ? Colors.white12 : Colors.black12),
                      width: isSelected ? 1.8 : 1.0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.25),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(cat.$2, size: 14, color: isSelected ? color : scheme.onSurfaceVariant),
                      const SizedBox(width: 5),
                      Text(
                        _language == VoiceLanguage.ml ? cat.$4 : cat.$3,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? (isDark ? Colors.white : color) : scheme.onSurfaceVariant,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.check_circle_rounded, size: 13, color: color),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _getStatusCaption() {
    if (_voiceState == VoiceState.listening) {
      if (_mode == VoiceReportMode.community) {
        return 'Listening... speak your ${_selectedCommunityType.label} naturally';
      } else if (_mode == VoiceReportMode.lostFound) {
        return 'Listening... speak what was lost or found';
      } else {
        return 'Listening... speak your civic issue naturally';
      }
    } else {
      if (_mode == VoiceReportMode.community) {
        return 'Tap microphone to speak ${_selectedCommunityType.label}';
      } else {
        return 'Tap microphone to speak or resume';
      }
    }
  }

  String _getTranscriptHint() {
    if (_mode == VoiceReportMode.civic) {
      return 'Speak your issue naturally... (e.g. "Huge pothole near East Fort bus stand with water leaking")';
    } else if (_mode == VoiceReportMode.lostFound) {
      return 'Speak what was lost or found... (e.g. "Lost brown leather wallet near Museum junction with ID card")';
    } else {
      switch (_selectedCommunityType) {
        case CommunityPostType.announcement:
          return 'Speak your announcement... (e.g. "Water supply maintenance this Sunday from 9 AM to 2 PM")';
        case CommunityPostType.poll:
          return 'Speak your poll question and choices... (e.g. "Should we fix the park swings? Yes, No")';
        case CommunityPostType.job:
          return 'Speak job or service needed... (e.g. "Need experienced electrician for house wiring in Kowdiar")';
        case CommunityPostType.general:
          return 'Speak your community discussion or question for neighbours...';
      }
    }
  }

  Widget _buildPhotoProofSection(bool isDark, ColorScheme scheme) {
    final isCivic = _mode == VoiceReportMode.civic;

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162032) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _attachedPhotoPath != null
              ? Colors.teal.withValues(alpha: 0.5)
              : (isCivic ? Colors.amber.withValues(alpha: 0.4) : (isDark ? Colors.white12 : Colors.black12)),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _attachedPhotoPath != null ? Icons.check_circle_rounded : Icons.photo_camera_rounded,
                    size: 16,
                    color: _attachedPhotoPath != null ? Colors.teal : (isCivic ? Colors.amber : scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Photo Proof Evidence',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _attachedPhotoPath != null ? Colors.teal : (isCivic ? Colors.amber : scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (_attachedPhotoPath != null ? Colors.teal : (isCivic ? Colors.amber : scheme.onSurfaceVariant))
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _attachedPhotoPath != null
                      ? 'Attached'
                      : (isCivic ? 'Required for Civic' : 'Optional'),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: _attachedPhotoPath != null ? Colors.teal : (isCivic ? Colors.amber : scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_attachedPhotoPath != null) ...[
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(_attachedPhotoPath!),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Photo proof ready',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Will be uploaded on submission',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Retake',
                  icon: const Icon(Icons.camera_alt_outlined, size: 20),
                  onPressed: () => _pickPhoto(ImageSource.camera),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                  onPressed: () => setState(() => _attachedPhotoPath = null),
                ),
              ],
            ),
          ] else ...[
            Text(
              isCivic
                  ? 'Attach photo evidence so field workers and civic admins can locate & resolve the issue faster.'
                  : 'Add a photo to help provide visual context for this report.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded, size: 16),
                    label: const Text('Camera', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded, size: 16),
                    label: const Text('Gallery', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

