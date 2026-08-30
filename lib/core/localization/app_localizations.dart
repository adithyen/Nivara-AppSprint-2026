import 'package:flutter/material.dart';
import '../../features/settings/language_controller.dart';

/// Meaningful, idiomatic civic localization dictionary for English, Hindi, and Malayalam.
abstract final class NivaraStrings {
  static const Map<String, Map<AppLanguage, String>> _dict = {
    // Brand & Tagline
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
    'welcome_user': {
      AppLanguage.en: 'Welcome',
      AppLanguage.hi: 'स्वागत है',
      AppLanguage.ml: 'സ്വാഗതം',
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

    // Navigation & Shells
    'nav_home': {
      AppLanguage.en: 'Home',
      AppLanguage.hi: 'होम',
      AppLanguage.ml: 'പ്രധാനം',
    },
    'nav_pulse': {
      AppLanguage.en: 'Pulse',
      AppLanguage.hi: 'पल्स (Pulse)',
      AppLanguage.ml: 'പൾസ്',
    },
    'nav_community': {
      AppLanguage.en: 'Community',
      AppLanguage.hi: 'समुदाय',
      AppLanguage.ml: 'സമൂഹം',
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
    'nav_tasks': {
      AppLanguage.en: 'Tasks',
      AppLanguage.hi: 'कार्य कतार',
      AppLanguage.ml: 'ചുമതലകൾ',
    },
    'nav_queue': {
      AppLanguage.en: 'Dispatch Queue',
      AppLanguage.hi: 'आवंटन कतार',
      AppLanguage.ml: 'വിഭാഗ നിര',
    },
    'nav_insights': {
      AppLanguage.en: 'City Insights',
      AppLanguage.hi: 'शहर रिपोर्ट एवं आंकड़े',
      AppLanguage.ml: 'നഗര സ്ഥിതിവിവരങ്ങൾ',
    },
    'nav_team': {
      AppLanguage.en: 'Staff & Team',
      AppLanguage.hi: 'फील्ड कर्मचारी टीम',
      AppLanguage.ml: 'ഫീൽഡ് ടീം',
    },

    // Home Screen Sections
    'civic_standing': {
      AppLanguage.en: 'Civic Standing & XP',
      AppLanguage.hi: 'नागरिक प्रतिष्ठा एवं स्कोर (XP)',
      AppLanguage.ml: 'പൗരസ്കോറും പദവിയും (XP)',
    },
    'civic_modules': {
      AppLanguage.en: 'Civic Modules',
      AppLanguage.hi: 'नागरिक सेवा मॉड्यूल',
      AppLanguage.ml: 'പൗരസേവന വിഭാഗങ്ങൾ',
    },
    'stat_reports': {
      AppLanguage.en: 'Reports',
      AppLanguage.hi: 'दर्ज शिकायतें',
      AppLanguage.ml: 'പരാതികൾ',
    },
    'stat_confirms': {
      AppLanguage.en: 'Confirms',
      AppLanguage.hi: 'सत्यापन',
      AppLanguage.ml: 'സ്ഥിരീകരണങ്ങൾ',
    },
    'stat_finds': {
      AppLanguage.en: 'Finds',
      AppLanguage.hi: 'प्राप्त वस्तुएं',
      AppLanguage.ml: 'കണ്ടെത്തിയവ',
    },
    'module_sensorwatch_sub': {
      AppLanguage.en: 'Highway & road pothole HUD',
      AppLanguage.hi: 'सड़क गड्ढे एवं कंपन टेलीमेट्री',
      AppLanguage.ml: 'റോഡിലെ കുഴികൾ കണ്ടെത്തൽ',
    },
    'module_report_sub': {
      AppLanguage.en: 'Report 19 civic issue categories',
      AppLanguage.hi: '19 नागरिक श्रेणियों में शिकायत दर्ज करें',
      AppLanguage.ml: '19 വിഭാഗങ്ങളിൽ പരാതി നൽകുക',
    },
    'module_map_sub': {
      AppLanguage.en: 'Real-time civic map & reports',
      AppLanguage.hi: 'लाइव शहर मानचित्र एवं रिपोर्ट',
      AppLanguage.ml: 'തത്സമയ നഗര ഭൂപടവും പരാതികളും',
    },
    'module_lost_found_sub': {
      AppLanguage.en: 'Radar item matching with QR pass',
      AppLanguage.hi: 'QR पास सहित खोई-पाई वस्तुएं',
      AppLanguage.ml: 'QR കോഡ് വഴിയുള്ള കണ്ടെത്തൽ',
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
    'coming_soon': {
      AppLanguage.en: 'Coming Soon',
      AppLanguage.hi: 'शीघ्र उपलब्ध',
      AppLanguage.ml: 'ഉടൻ ലഭ്യമാകും',
    },
    'active': {
      AppLanguage.en: 'Active',
      AppLanguage.hi: 'सक्रिय',
      AppLanguage.ml: 'സജീവം',
    },

    // Work With Nivara
    'work_with_nivara': {
      AppLanguage.en: 'Work with Nivara',
      AppLanguage.hi: 'निवारा के साथ कार्य करें',
      AppLanguage.ml: 'നിവാരയോടൊപ്പം പ്രവർത്തിക്കുക',
    },
    'work_with_nivara_sub': {
      AppLanguage.en: 'Become a verified field worker in your ward',
      AppLanguage.hi: 'अपने वार्ड में प्रमाणित फील्ड कार्यकर्ता बनें',
      AppLanguage.ml: 'നിങ്ങളുടെ വാർഡിലെ ഫീൽഡ് ജീവനക്കാരനാകൂ',
    },
    'workforce_application': {
      AppLanguage.en: 'Municipal Field Workforce Application',
      AppLanguage.hi: 'नगर निगम फील्ड कार्यबल आवेदन',
      AppLanguage.ml: 'നഗരസഭാ ഫീൽഡ് വർക്ക് അപേക്ഷ',
    },
    'full_legal_name': {
      AppLanguage.en: 'Full Legal Name',
      AppLanguage.hi: 'पूरा कानूनी नाम',
      AppLanguage.ml: 'പൂർണ്ണമായ പേര്',
    },
    'phone_contact': {
      AppLanguage.en: 'Contact Phone Number',
      AppLanguage.hi: 'संपर्क फोन नंबर',
      AppLanguage.ml: 'ഫോൺ നമ്പർ',
    },
    'ward_neighborhood': {
      AppLanguage.en: 'Assigned Ward / Neighborhood',
      AppLanguage.hi: 'वार्ड / मोहल्ला',
      AppLanguage.ml: 'വാർഡ് / പ്രദേശം',
    },
    'field_of_interest': {
      AppLanguage.en: 'Field of Expertise & Department',
      AppLanguage.hi: 'कार्य क्षेत्र एवं विभाग',
      AppLanguage.ml: 'താല്പര്യമുള്ള മേഖല / വകുപ്പ്',
    },
    'submit_application': {
      AppLanguage.en: 'Submit Verified Application',
      AppLanguage.hi: 'आवेदन पत्र जमा करें',
      AppLanguage.ml: 'അപേക്ഷ സമർപ്പിക്കുക',
    },
    'app_submitted_success': {
      AppLanguage.en: 'Application Submitted Successfully!',
      AppLanguage.hi: 'आवेदन सफलतापूर्वक जमा हो गया!',
      AppLanguage.ml: 'അപേക്ഷ വിജയകരമായി സമർപ്പിച്ചു!',
    },
    'app_dispatched_msg': {
      AppLanguage.en: 'Your application has been dispatched to municipal administrators for review and ward allocation.',
      AppLanguage.hi: 'आपका आवेदन नगर निगम अधिकारियों को समीक्षा एवं वार्ड आवंटन हेतु भेज दिया गया है।',
      AppLanguage.ml: 'നിങ്ങളുടെ അപേക്ഷ നഗരസഭാ ഉദ്യോഗസ്ഥരുടെ പരിശോധനയ്ക്കായി അയച്ചിരിക്കുന്നു.',
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

    // Report Filing Form
    'report_civic_issue': {
      AppLanguage.en: 'Report Civic Issue',
      AppLanguage.hi: 'नागरिक समस्या दर्ज करें',
      AppLanguage.ml: 'പരാതി രേഖപ്പെടുത്തുക',
    },
    'issue_title': {
      AppLanguage.en: 'Issue Title / Summary',
      AppLanguage.hi: 'समस्या का शीर्षक / विवरण',
      AppLanguage.ml: 'വിഷയം / ചുരുക്കം',
    },
    'issue_category': {
      AppLanguage.en: 'Category',
      AppLanguage.hi: 'श्रेणी (Category)',
      AppLanguage.ml: 'വിഭാഗം (Category)',
    },
    'issue_description': {
      AppLanguage.en: 'Detailed Description',
      AppLanguage.hi: 'विस्तृत विवरण',
      AppLanguage.ml: 'വിശദ വിവരണം',
    },
    'issue_severity': {
      AppLanguage.en: 'Severity Level',
      AppLanguage.hi: 'गंभीरता का स्तर (Severity)',
      AppLanguage.ml: 'തീവ്രത (Severity)',
    },
    'photo_evidence': {
      AppLanguage.en: 'Photo Evidence',
      AppLanguage.hi: 'फोटो साक्ष्य',
      AppLanguage.ml: 'ഫോട്ടോ തെളിവുകൾ',
    },
    'location_address': {
      AppLanguage.en: 'Location & Address',
      AppLanguage.hi: 'स्थान एवं पता',
      AppLanguage.ml: 'സ്ഥലവും വിലാസവും',
    },
    'pick_on_map': {
      AppLanguage.en: 'Pick Exact Pin on Map',
      AppLanguage.hi: 'मानचित्र पर सही स्थान चुनें',
      AppLanguage.ml: 'മാപ്പിൽ സ്ഥലം അടയാളപ്പെടുത്തുക',
    },
    'submit_report_button': {
      AppLanguage.en: 'Submit Cryptographically Sealed Report',
      AppLanguage.hi: 'डिजिटल मुहर सहित शिकायत दर्ज करें',
      AppLanguage.ml: 'പരാതി ഔദ്യോഗികമായി സമർപ്പിക്കുക',
    },

    // Lost & Found
    'report_lost_item': {
      AppLanguage.en: 'Report Lost Item',
      AppLanguage.hi: 'खोई वस्तु की सूचना दें',
      AppLanguage.ml: 'നഷ്ടപ്പെട്ട സാധനം രേഖപ്പെടുത്തുക',
    },
    'report_found_item': {
      AppLanguage.en: 'Report Found Item',
      AppLanguage.hi: 'पाई गई वस्तु की सूचना दें',
      AppLanguage.ml: 'കണ്ടുകിട്ടിയ സാധനം രേഖപ്പെടുത്തുക',
    },
    'my_listings': {
      AppLanguage.en: 'My Listings',
      AppLanguage.hi: 'मेरी लिस्टिंग',
      AppLanguage.ml: 'എന്റെ ലിസ്റ്റിംഗുകൾ',
    },
    'matching_radar': {
      AppLanguage.en: 'Discovery Radar',
      AppLanguage.hi: 'खोज रडार (Discovery Radar)',
      AppLanguage.ml: 'റഡാർ മാച്ചിംഗ്',
    },
    'all_items': {
      AppLanguage.en: 'All Items',
      AppLanguage.hi: 'सभी वस्तुएं',
      AppLanguage.ml: 'എല്ലാം',
    },
    'lost_tab': {
      AppLanguage.en: 'Lost',
      AppLanguage.hi: 'खोया हुआ',
      AppLanguage.ml: 'നഷ്ടപ്പെട്ടത്',
    },
    'found_tab': {
      AppLanguage.en: 'Found',
      AppLanguage.hi: 'കണ്ടുകിട്ടിയത്',
      AppLanguage.ml: 'കണ്ടുകിട്ടിയത്',
    },
    'handover_pass': {
      AppLanguage.en: 'QR Handover Pass',
      AppLanguage.hi: 'QR हस्तांतरण पास',
      AppLanguage.ml: 'QR കൈമാറ്റ പാസ്',
    },

    // SensorWatch
    'sensorwatch_title': {
      AppLanguage.en: 'SensorWatch Road Telemetry',
      AppLanguage.hi: 'सड़क सेंसर वॉच टेलीमेट्री',
      AppLanguage.ml: 'റോഡ് സെൻസർ വാച്ച് ടെലിമെട്രി',
    },
    'sensorwatch_start': {
      AppLanguage.en: 'Start Road Monitor',
      AppLanguage.hi: 'सड़क निगरानी शुरू करें',
      AppLanguage.ml: 'നിരീക്ഷണം ആരംഭിക്കുക',
    },
    'sensorwatch_stop': {
      AppLanguage.en: 'Stop Monitoring',
      AppLanguage.hi: 'निगरानी रोकें',
      AppLanguage.ml: 'നിരീക്ഷണം നിർത്തുക',
    },
    'pothole_detected': {
      AppLanguage.en: 'Road Impact / Pothole Logged',
      AppLanguage.hi: 'सड़क गड्ढा / झटका दर्ज हुआ',
      AppLanguage.ml: 'റോഡിലെ കുഴി രേഖപ്പെടുത്തി',
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
    'status_acknowledged': {
      AppLanguage.en: 'Acknowledged',
      AppLanguage.hi: 'स्वीकार किया गया',
      AppLanguage.ml: 'സ്വീകരിച്ചു',
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
    'status_closed': {
      AppLanguage.en: 'Closed',
      AppLanguage.hi: 'बंद कर दिया गया',
      AppLanguage.ml: 'പൂർത്തിയായി',
    },
    'status_duplicate': {
      AppLanguage.en: 'Duplicate',
      AppLanguage.hi: 'समान शिकायत',
      AppLanguage.ml: 'മറ്റൊരു പരാതിയുണ്ട്',
    },
  };

  /// Translate a string key for a given language.
  static String tr(String key, AppLanguage lang) {
    final entry = _dict[key];
    if (entry == null) return key;
    return entry[lang] ?? entry[AppLanguage.en] ?? key;
  }
}
