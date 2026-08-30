import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme.dart';
import '../../core/widgets/bouncy_tap.dart';
import 'accessibility_controller.dart';
import 'language_controller.dart';

/// Dedicated App Language selector screen.
class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key});

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final currentLang = ref.watch(languageControllerProvider);
    final langCtrl = ref.read(languageControllerProvider.notifier);
    final a11y = ref.watch(accessibilityControllerProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final cardBg = isDark ? const Color(0xFF10161E) : Colors.white;
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0);

    final filteredIndianLangs = kAllIndianOfficialLanguages.where((lang) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return lang.name.toLowerCase().contains(q) ||
          lang.nativeName.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          NivaraStrings.tr('settings_language', currentLang),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          // Header Notice
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF162332), const Color(0xFF0F1722)]
                    : [const Color(0xFFEBF5FF), const Color(0xFFF1F5F9)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: NivaraColors.primaryBlue.withValues(alpha: isDark ? 0.3 : 0.4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: NivaraColors.primaryBlue.withValues(alpha: isDark ? 0.2 : 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.translate_rounded,
                    color: NivaraColors.primaryBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Multilingual Civic Access',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select your preferred language. All buttons, civic terms, and statuses will adapt instantly.',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Primary Fully-Localized Languages (EN, HI, ML)
          const Text(
            'Fully Supported Languages',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          ),
          const SizedBox(height: 10),

          for (final lang in AppLanguage.values) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: BouncyTap(
                onTap: () {
                  if (a11y.hapticsEnabled) HapticFeedback.mediumImpact();
                  langCtrl.setLanguage(lang);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: currentLang == lang
                        ? primary.withValues(alpha: isDark ? 0.18 : 0.12)
                        : cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: currentLang == lang
                          ? primary
                          : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                      width: currentLang == lang ? 2.0 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Text(lang.flag, style: const TextStyle(fontSize: 26)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lang.nativeName,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: currentLang == lang ? primary : null,
                              ),
                            ),
                            Text(
                              lang.englishName,
                              style: TextStyle(
                                color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (currentLang == lang)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Colors.black,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 28),

          // 22 Official Scheduled Languages of India
          const Text(
            'Official Languages of India',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          ),
          const SizedBox(height: 4),
          Text(
            'Search from all 22 official Eighth Schedule languages of India:',
            style: TextStyle(
              color: isDark ? Colors.white54 : const Color(0xFF64748B),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),

          // Search Field
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'Search language (e.g. Tamil, Kannada, Marathi)...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: borderColor),
              ),
            ),
          ),

          const SizedBox(height: 14),

          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredIndianLangs.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
              ),
              itemBuilder: (context, index) {
                final item = filteredIndianLangs[index];
                final isSelected = currentLang.code == item.code;

                return ListTile(
                  title: Text(
                    item.nativeName,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isSelected ? primary : null,
                    ),
                  ),
                  subtitle: Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    ),
                  ),
                  trailing: item.isFullyLocalized
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: NivaraColors.success.withValues(alpha: isDark ? 0.2 : 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: NivaraColors.success.withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(
                              color: NivaraColors.success,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            NivaraStrings.tr('coming_soon', currentLang),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                  onTap: () {
                    if (item.isFullyLocalized) {
                      final target = AppLanguage.fromCode(item.code);
                      langCtrl.setLanguage(target);
                      if (a11y.hapticsEnabled) HapticFeedback.mediumImpact();
                    } else {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(
                              '${item.name} (${item.nativeName}) is coming soon. Defaulting to English interface with regional geocoding.',
                            ),
                          ),
                        );
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
