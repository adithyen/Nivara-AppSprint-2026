import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

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
  Function(VoiceReportPayload)? onPayloadReady,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => VoiceReportingSheet(
      initialMode: initialMode,
      onPayloadReady: onPayloadReady,
    ),
  );
}

/// Comprehensive, glassmorphic Voice Reporting Sheet featuring Emil-motion
/// physics, real-time speech-to-text, and automatic slot extraction across
/// Civic, Lost & Found, and Community reporting workflows.
class VoiceReportingSheet extends ConsumerStatefulWidget {
  final VoiceReportMode? initialMode;
  final Function(VoiceReportPayload)? onPayloadReady;

  const VoiceReportingSheet({
    super.key,
    this.initialMode,
    this.onPayloadReady,
  });

  @override
  ConsumerState<VoiceReportingSheet> createState() => _VoiceReportingSheetState();
}

class _VoiceReportingSheetState extends ConsumerState<VoiceReportingSheet> {
  late VoiceReportMode _mode;
  VoiceLanguage _language = VoiceLanguage.en;
  VoiceState _voiceState = VoiceState.idle;
  double _soundLevel = 0.0;
  String _liveTranscript = '';
  VoiceReportPayload? _parsedPayload;
  bool _isSubmitting = false;

  Position? _currentPosition;
  String? _currentAddress;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ?? VoiceReportMode.civic;

    // Match current app language if possible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appLang = ref.read(languageControllerProvider);
      if (appLang == AppLanguage.ml) {
        _language = VoiceLanguage.ml;
      } else if (appLang == AppLanguage.hi) {
        _language = VoiceLanguage.hi;
      }
      setState(() {});
      _fetchLocation();
      _startVoiceListening();
    });
  }

  @override
  void dispose() {
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
      onSoundLevel: (level) {
        if (mounted) setState(() => _soundLevel = level);
      },
      onStateChanged: (state) {
        if (mounted) setState(() => _voiceState = state);
      },
      onResult: (text, isFinal) async {
        if (!mounted) return;
        setState(() => _liveTranscript = text);

        if (text.trim().isNotEmpty) {
          final parser = ref.read(voiceIntentParserServiceProvider);
          final payload = await parser.parseTranscript(
            text,
            forcedMode: _mode,
            language: _language,
          );
          if (mounted) {
            setState(() {
              _parsedPayload = payload;
              if (payload.mode != _mode && widget.initialMode == null) {
                _mode = payload.mode;
              }
            });
          }
        }
      },
    );

    if (!started && mounted) {
      setState(() => _voiceState = VoiceState.idle);
    }
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

  Future<void> _runSimulation(String sampleText) async {
    setState(() {
      _liveTranscript = '';
      _voiceState = VoiceState.listening;
    });

    await ref.read(voiceRecognitionServiceProvider).simulateDictation(
      text: sampleText,
      onSoundLevel: (level) {
        if (mounted) setState(() => _soundLevel = level);
      },
      onResult: (text, isFinal) async {
        if (!mounted) return;
        setState(() => _liveTranscript = text);

        if (text.trim().isNotEmpty) {
          final parser = ref.read(voiceIntentParserServiceProvider);
          final payload = await parser.parseTranscript(
            text,
            forcedMode: _mode,
            language: _language,
          );
          if (mounted) {
            setState(() {
              _parsedPayload = payload;
              if (payload.mode != _mode && widget.initialMode == null) {
                _mode = payload.mode;
              }
              if (isFinal) _voiceState = VoiceState.completed;
            });
          }
        }
      },
    );
  }

  Future<void> _submit1Tap() async {
    if (_parsedPayload == null || _liveTranscript.trim().isEmpty) return;
    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    final profile = ref.read(authControllerProvider).asData?.value;
    final uid = profile?.id ?? supabase.auth.currentUser?.id;

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
            lat: _currentPosition?.latitude ?? kDefaultLat,
            lng: _currentPosition?.longitude ?? kDefaultLng,
            address: _parsedPayload!.extractedLandmark ?? _currentAddress,
            source: 'MANUAL',
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
            'post_type': _parsedPayload!.communityType.wire,
            'title': _parsedPayload!.title,
            'body': _parsedPayload!.description,
            'lat': _currentPosition?.latitude ?? kDefaultLat,
            'lng': _currentPosition?.longitude ?? kDefaultLng,
            'location_label': _parsedPayload!.extractedLandmark ?? _currentAddress,
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
    if (_parsedPayload == null) return;
    Navigator.of(context).pop();

    if (widget.onPayloadReady != null) {
      widget.onPayloadReady!(_parsedPayload!);
      return;
    }

    switch (_mode) {
      case VoiceReportMode.civic:
        context.push(
          '/report',
          extra: {
            'category': _parsedPayload!.civicCategory,
            'title': _parsedPayload!.title,
            'description': _parsedPayload!.description,
            'severity': _parsedPayload!.severity,
            'address': _parsedPayload!.extractedLandmark ?? _currentAddress,
            'lat': _currentPosition?.latitude ?? kDefaultLat,
            'lng': _currentPosition?.longitude ?? kDefaultLng,
          },
        );
        break;

      case VoiceReportMode.lostFound:
        if (_parsedPayload!.lfItemType == LFItemType.lost) {
          context.push('/lostfound/lost');
        } else {
          context.push('/lostfound/found');
        }
        break;

      case VoiceReportMode.community:
        context.push('/community/compose');
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
                                .parseTranscript(_liveTranscript, forcedMode: mode, language: _language)
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

            const SizedBox(height: 18),

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
                _voiceState == VoiceState.listening
                    ? 'Listening... speak your issue naturally'
                    : 'Tap microphone to speak or resume',
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

            // Live Transcript Card
            Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131F37) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: Text(
                _liveTranscript.isNotEmpty
                    ? '"$_liveTranscript"'
                    : 'e.g. "Huge pothole near East Fort bus stand with water leaking"',
                style: TextStyle(
                  fontSize: 13.5,
                  fontStyle: _liveTranscript.isEmpty ? FontStyle.italic : FontStyle.normal,
                  color: _liveTranscript.isNotEmpty
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  height: 1.4,
                ),
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

            // Quick Demo Chips
            const SizedBox(height: 12),
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildDemoChip('Huge pothole near East Fort junction'),
                  _buildDemoChip('കിഴക്കേകോട്ടയിൽ വാലറ്റ് നഷ്ടപ്പെട്ടു'),
                  _buildDemoChip('Ward 12 cleanliness drive this Sunday'),
                ],
              ),
            ),

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

  Widget _buildDemoChip(String text) {
    return GestureDetector(
      onTap: () => _runSimulation(text),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow_rounded, size: 14, color: Color(0xFF00FFCC)),
            const SizedBox(width: 4),
            Text(
              text,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
