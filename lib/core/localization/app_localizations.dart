import 'package:flutter/material.dart';
import '../../features/settings/language_controller.dart';

/// Meaningful, idiomatic civic localization dictionary for English, Hindi, and Malayalam.
abstract final class NivaraStrings {
  static const Map<String, Map<AppLanguage, String>> _dict = {
    // Brand
    'app_name': {
      AppLanguage.en: 'Nivara',
      AppLanguage.hi: 'निवारा',
      AppLanguage.ml: 'നിവാര',
    },
    'app_tagline': {
      AppLanguage.en: 'Next-Gen Civic Action & Municipal Telemetry',
      AppLanguage.hi: 'नागरिक सेवा एवं नगरपालिका कार्य प्रणाली',
      AppLanguage.ml: 'പൗരസേവനവും നഗരസഭാ പ്രവർത്തനങ്ങളും',
    },

    // Roles
    'role_citizen': {
      AppLanguage.en: 'Citizen',
      AppLanguage.hi: 'नागरिक',
      AppLanguage.ml: 'പൗരൻ',
    },
    'role_worker': {
      AppLanguage.en: 'Field Worker',
      AppLanguage.hi: 'फील्ड कर्मचारी',
      AppLanguage.ml: 'ഫീൽഡ് ജീവനക്കാരൻ',
    },
    'role_admin': {
      AppLanguage.en: 'Municipal Officer',
      AppLanguage.hi: 'नगर निगम अधिकारी',
      AppLanguage.ml: 'നഗരസഭാ ഉദ്യോഗസ്ഥൻ',
    },

    // Navigation & Headers
    'nav_home': {
      AppLanguage.en: 'Home',
      AppLanguage.hi: 'होम',
      AppLanguage.ml: 'പ്രധാനം',
    },
    'nav_map': {
      AppLanguage.en: 'Civic Map',
      AppLanguage.hi: 'नागरिक मानचित्र',
      AppLanguage.ml: 'നഗര ഭൂപടം',
    },
    'nav_report': {
      AppLanguage.en: 'Report Issue',
      AppLanguage.hi: 'समस्या दर्ज करें',
      AppLanguage.ml: 'പരാതി നൽകുക',
    },
    'nav_lost_found': {
      AppLanguage.en: 'Lost & Found',
      AppLanguage.hi: 'खोया और पाया',
      AppLanguage.ml: 'നഷ്ടപ്പെട്ടതും കണ്ടെത്തിയതും',
    },
    'nav_profile': {
      AppLanguage.en: 'Profile',
      AppLanguage.hi: 'प्रोफाइल',
      AppLanguage.ml: 'പ്രൊഫൈൽ',
    },
    'nav_sensor_watch': {
      AppLanguage.en: 'SensorWatch',
      AppLanguage.hi: 'सड़क सेंसर वॉच',
      AppLanguage.ml: 'റോഡ് സെൻസർ വാച്ച്',
    },

    // Settings & Options
    'settings_appearance': {
      AppLanguage.en: 'Appearance',
      AppLanguage.hi: 'दिखावट एवं थीम',
      AppLanguage.ml: 'ഡിസൈനും തീമും',
    },
    'settings_accessibility': {
      AppLanguage.en: 'Accessibility',
      AppLanguage.hi: 'सुलभता एवं सहायक सुविधाएं',
      AppLanguage.ml: 'സഹായ സൗകര്യങ്ങൾ (Accessibility)',
    },
    'settings_language': {
      AppLanguage.en: 'App Language',
      AppLanguage.hi: 'भाषा (Language)',
      AppLanguage.ml: 'ഭാഷ (Language)',
    },

    // Profile Actions
    'edit_profile': {
      AppLanguage.en: 'Edit Profile',
      AppLanguage.hi: 'प्रोफाइल संपादित करें',
      AppLanguage.ml: 'പ്രൊഫൈൽ പുതുക്കുക',
    },
    'activity_timeline': {
      AppLanguage.en: 'My Activity Timeline',
      AppLanguage.hi: 'मेरी गतिविधि का विवरण',
      AppLanguage.ml: 'എന്റെ പ്രവർത്തനങ്ങൾ',
    },
    'pending_sync': {
      AppLanguage.en: 'Pending Offline Queue',
      AppLanguage.hi: 'ऑफ़लाइन सिंक कतार',
      AppLanguage.ml: 'ഓഫ്‌ലൈൻ സമന്വയ നിര',
    },
    'report_issue_dev': {
      AppLanguage.en: 'Report Issue / Contact Developer',
      AppLanguage.hi: 'समस्या बताएं / डेवलपर से संपर्क करें',
      AppLanguage.ml: 'സഹായം / ഡെവലപ്പറെ ബന്ധപ്പെടുക',
    },
    'sign_out': {
      AppLanguage.en: 'Sign Out',
      AppLanguage.hi: 'साइन आउट करें',
      AppLanguage.ml: 'ലോഗ് ഔട്ട് ചെയ്യുക',
    },

    // Admin Specific
    'admin_command_center': {
      AppLanguage.en: 'Municipal Command Center',
      AppLanguage.hi: 'नगर निगम नियंत्रण केंद्र',
      AppLanguage.ml: 'നഗരസഭാ കമാൻഡ് സെന്റർ',
    },
    'admin_dispatched_tasks': {
      AppLanguage.en: 'Dispatched Tasks',
      AppLanguage.hi: 'आवंटित कार्य',
      AppLanguage.ml: 'നൽകിയ ചുമതലകൾ',
    },
    'admin_sla_efficiency': {
      AppLanguage.en: 'Resolution Efficiency',
      AppLanguage.hi: 'समाधान दर एवं दक्षता',
      AppLanguage.ml: 'പരിഹാര കാര്യക്ഷമത',
    },
    'admin_supervised_workers': {
      AppLanguage.en: 'Supervised Team',
      AppLanguage.hi: 'निगरानी टीम',
      AppLanguage.ml: 'ഫീൽഡ് ജീവനക്കാർ',
    },

    // Accessibility Strings
    'a11y_high_contrast': {
      AppLanguage.en: 'High Contrast Mode',
      AppLanguage.hi: 'उच्च कंट्रास्ट मोड',
      AppLanguage.ml: 'ഹൈ കോൺട്രാസ്റ്റ് മോഡ്',
    },
    'a11y_reduce_motion': {
      AppLanguage.en: 'Reduce Motion',
      AppLanguage.hi: 'कम गति (Reduce Motion)',
      AppLanguage.ml: 'ചലനങ്ങൾ കുറയ്ക്കുക',
    },
    'a11y_color_blind': {
      AppLanguage.en: 'Color Blindness Shape Markers',
      AppLanguage.hi: 'वर्णांधता सहायक प्रतीक (CVD)',
      AppLanguage.ml: 'കളർ ബ്ലൈൻഡ് സഹായ ചിഹ്നങ്ങൾ',
    },
    'a11y_text_scale': {
      AppLanguage.en: 'In-App Text Scaling',
      AppLanguage.hi: 'अक्षर का आकार (Text Scaling)',
      AppLanguage.ml: 'അക്ഷരങ്ങളുടെ വലിപ്പം',
    },
    'a11y_haptics': {
      AppLanguage.en: 'Haptic Vibration Feedback',
      AppLanguage.hi: 'स्पर्श कंपन प्रतिक्रिया (Haptics)',
      AppLanguage.ml: 'വൈബ്രേഷൻ ഫീഡ്‌ബാക്ക്',
    },
    'a11y_voice_alerts': {
      AppLanguage.en: 'TalkBack Spoken Alerts',
      AppLanguage.hi: 'ध्वनि सूचनाएं (Screen Reader)',
      AppLanguage.ml: 'ശബ്ദ അറിയിപ്പുകൾ (TalkBack)',
    },

    // Status
    'status_submitted': {
      AppLanguage.en: 'Submitted',
      AppLanguage.hi: 'दर्ज किया गया',
      AppLanguage.ml: 'രേഖപ്പെടുത്തി',
    },
    'status_in_progress': {
      AppLanguage.en: 'In Progress',
      AppLanguage.hi: 'प्रगति पर',
      AppLanguage.ml: 'നടപപടിയിൽ',
    },
    'status_resolved': {
      AppLanguage.en: 'Resolved',
      AppLanguage.hi: 'समाधान हो गया',
      AppLanguage.ml: 'പരിഹരിച്ചു',
    },
  };

  /// Translate a string key for a given language.
  static String tr(String key, AppLanguage lang) {
    final entry = _dict[key];
    if (entry == null) return key;
    return entry[lang] ?? entry[AppLanguage.en] ?? key;
  }
}
