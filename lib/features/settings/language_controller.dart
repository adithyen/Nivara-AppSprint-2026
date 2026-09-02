import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported application language codes.
enum AppLanguage {
  en('en', 'English', 'English', '🇬🇧'),
  hi('hi', 'हिन्दी', 'Hindi', '🇮🇳'),
  ml('ml', 'മലയാളം', 'Malayalam', '🇮🇳');

  final String code;
  final String nativeName;
  final String englishName;
  final String flag;

  const AppLanguage(this.code, this.nativeName, this.englishName, this.flag);

  static AppLanguage fromCode(String? code) {
    if (code == null) return AppLanguage.en;
    return values.firstWhere((e) => e.code == code, orElse: () => AppLanguage.en);
  }
}

/// Official languages of India registry.
class IndianLanguageInfo {
  final String code;
  final String name;
  final String nativeName;
  final bool isFullyLocalized;

  const IndianLanguageInfo({
    required this.code,
    required this.name,
    required this.nativeName,
    this.isFullyLocalized = false,
  });
}

const List<IndianLanguageInfo> kAllIndianOfficialLanguages = [
  IndianLanguageInfo(code: 'en', name: 'English', nativeName: 'English', isFullyLocalized: true),
  IndianLanguageInfo(code: 'hi', name: 'Hindi', nativeName: 'हिन्दी', isFullyLocalized: true),
  IndianLanguageInfo(code: 'ml', name: 'Malayalam', nativeName: 'മലയാളം', isFullyLocalized: true),
  IndianLanguageInfo(code: 'kn', name: 'Kannada', nativeName: 'ಕನ್ನಡ'),
  IndianLanguageInfo(code: 'ta', name: 'Tamil', nativeName: 'தமிழ்'),
  IndianLanguageInfo(code: 'te', name: 'Telugu', nativeName: 'తెలుగు'),
  IndianLanguageInfo(code: 'mr', name: 'Marathi', nativeName: 'मराठी'),
  IndianLanguageInfo(code: 'bn', name: 'Bengali', nativeName: 'বাংলা'),
  IndianLanguageInfo(code: 'gu', name: 'Gujarati', nativeName: 'ગુજરાતી'),
  IndianLanguageInfo(code: 'pa', name: 'Punjabi', nativeName: 'ਪੰਜਾਬੀ'),
  IndianLanguageInfo(code: 'or', name: 'Odia', nativeName: 'ଓଡ଼ିଆ'),
  IndianLanguageInfo(code: 'as', name: 'Assamese', nativeName: 'অসমীয়া'),
  IndianLanguageInfo(code: 'ur', name: 'Urdu', nativeName: 'اردو'),
  IndianLanguageInfo(code: 'sa', name: 'Sanskrit', nativeName: 'संस्कृतम्'),
  IndianLanguageInfo(code: 'ks', name: 'Kashmiri', nativeName: 'کٲشُر'),
  IndianLanguageInfo(code: 'sd', name: 'Sindhi', nativeName: 'سنڌي'),
  IndianLanguageInfo(code: 'ne', name: 'Nepali', nativeName: 'नेपाली'),
  IndianLanguageInfo(code: 'kok', name: 'Konkani', nativeName: 'कोंकणी'),
  IndianLanguageInfo(code: 'mni', name: 'Manipuri', nativeName: 'ꯃꯩꯇꯩꯂꯣꯟ'),
  IndianLanguageInfo(code: 'brx', name: 'Bodo', nativeName: 'बर’'),
  IndianLanguageInfo(code: 'sat', name: 'Santali', nativeName: 'ᱥᱟᱱᱛᱟᱲᱤ'),
  IndianLanguageInfo(code: 'mai', name: 'Maithili', nativeName: 'मैथिली'),
  IndianLanguageInfo(code: 'doi', name: 'Dogri', nativeName: 'डोगरी'),
];

/// Riverpod provider for managing active AppLanguage.
final languageControllerProvider =
    NotifierProvider<LanguageController, AppLanguage>(LanguageController.new);

class LanguageController extends Notifier<AppLanguage> {
  static const _kPrefKey = 'app_language_code';

  @override
  AppLanguage build() {
    _load();
    return AppLanguage.en;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kPrefKey);
    state = AppLanguage.fromCode(code);
  }

  Future<void> setLanguage(AppLanguage lang) async {
    state = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, lang.code);
  }
}
