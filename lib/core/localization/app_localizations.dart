import 'package:flutter/material.dart';
import '../../features/settings/language_controller.dart';
import '../../models/enums.dart';

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
    'role_superadmin': {
      AppLanguage.en: 'Super Admin',
      AppLanguage.hi: 'मुख्य प्रशासक',
      AppLanguage.ml: 'മുഖ്യ അഡ്മിൻ',
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
      AppLanguage.hi: 'नागरिक प्रतिष्ठा एवं XP',
      AppLanguage.ml: 'പൗരസ്കോറും പദവിയും (XP)',
    },
    'civic_modules': {
      AppLanguage.en: 'Civic Modules',
      AppLanguage.hi: 'नागरिक सेवा मॉड्यूल',
      AppLanguage.ml: 'പൗരസേവന വിഭാഗങ്ങൾ',
    },
    'stat_reports': {
      AppLanguage.en: 'Reports',
      AppLanguage.hi: 'शिकायतें',
      AppLanguage.ml: 'പരാതികൾ',
    },
    'stat_confirms': {
      AppLanguage.en: 'Confirms',
      AppLanguage.hi: 'सत्यापन',
      AppLanguage.ml: 'സ്ഥിരീകരണങ്ങൾ',
    },
    'stat_finds': {
      AppLanguage.en: 'Finds',
      AppLanguage.hi: 'കണ്ടെത്തിയവ',
      AppLanguage.ml: 'കണ്ടെത്തിയവ',
    },
    'xp_points': {
      AppLanguage.en: 'XP Points',
      AppLanguage.hi: 'XP अंक',
      AppLanguage.ml: 'XP പോയിന്റുകൾ',
    },
    'pts_to_level': {
      AppLanguage.en: 'pts to Level',
      AppLanguage.hi: 'अंक शेष लेवल',
      AppLanguage.ml: 'പോയിന്റുകൾ അടുത്ത ലെവലിലേക്ക്',
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
    'sub_appearance': {
      AppLanguage.en: 'Theme mode (Light/Dark) and brand accent colour',
      AppLanguage.hi: 'थीम मोड (लाइट/डार्क) एवं ब्रांड रंग',
      AppLanguage.ml: 'തീം മോഡും (Light/Dark) നിറങ്ങളും',
    },
    'settings_accessibility': {
      AppLanguage.en: 'Accessibility',
      AppLanguage.hi: 'सुलभता',
      AppLanguage.ml: 'പ്രവേശനക്ഷമത',
    },
    'sub_accessibility': {
      AppLanguage.en: 'Text scaling, high contrast, colour correction, remove animations & haptics',
      AppLanguage.hi: 'टेक्स्ट स्केलिंग, उच्च कंट्रास्ट, रंग सुधार, एनिमेशन एवं कंपन',
      AppLanguage.ml: 'ടെക്സ്റ്റ് വലുപ്പം, ഹൈ കോൺട്രാസ്റ്റ്, കളർ കറക്ഷൻ, വൈബ്രേഷൻ',
    },
    'settings_language': {
      AppLanguage.en: 'App Language',
      AppLanguage.hi: 'भाषा (Language)',
      AppLanguage.ml: 'ഭാഷ (Language)',
    },
    'sub_language': {
      AppLanguage.en: 'English • हिन्दी • മലയാളം and 22 Indian languages',
      AppLanguage.hi: 'अंग्रेजी, हिन्दी, मलयालम सहित 22 भाषाएं',
      AppLanguage.ml: 'ഇംഗ്ലീഷ്, ഹിന്ദി, മലയാളം ഉൾപ്പെടെ 22 ഭാഷകൾ',
    },
    'sub_timeline': {
      AppLanguage.en: 'Full history of your filed reports, confirmations, and finds',
      AppLanguage.hi: 'आपकी शिकायतों, सत्यापनों और प्राप्तियों का संपूर्ण इतिहास',
      AppLanguage.ml: 'നിങ്ങൾ നൽകിയ പരാതികളുടെയും കണ്ടെത്തലുകളുടെയും ചരിത്രം',
    },
    'sub_pending_sync': {
      AppLanguage.en: 'View and manage locally queued offline actions',
      AppLanguage.hi: 'स्थानीय रूप से सहेजी गई ऑफ़लाइन क्रियाएं प्रबंधित करें',
      AppLanguage.ml: 'ഓഫ്‌ലൈൻ സമന്വയ നിര പരിശോധിക്കുക',
    },
    'sub_contact_dev': {
      AppLanguage.en: 'Submit feedback or report application bugs',
      AppLanguage.hi: 'प्रतिक्रिया भेजें या बग की सूचना दें',
      AppLanguage.ml: 'അഭിപ്രായങ്ങൾ രേഖപ്പെടുത്തുക / ബന്ധപ്പെടുക',
    },
    'sub_sign_out': {
      AppLanguage.en: 'Sign out of your Nivara account',
      AppLanguage.hi: 'अपने निवारा खाते से साइन आउट करें',
      AppLanguage.ml: 'നിവാര അക്കൗണ്ടിൽ നിന്ന് ലോഗ് ഔട്ട് ചെയ്യുക',
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

    // Language Screen
    'lang_banner_title': {
      AppLanguage.en: 'Multilingual Civic Access',
      AppLanguage.hi: 'बहुभाषी नागरिक पहुंच',
      AppLanguage.ml: 'ബഹുഭാഷാ പൗരസേവനം',
    },
    'lang_banner_sub': {
      AppLanguage.en: 'Select your preferred language. All buttons, civic terms, and statuses will adapt instantly.',
      AppLanguage.hi: 'अपनी पसंदीदा भाषा चुनें। सभी बटन, नागरिक शब्द और स्थितियां तुरंत बदल जाएंगी।',
      AppLanguage.ml: 'നിങ്ങളുടെ ഭാഷ തിരഞ്ഞെടുക്കുക. എല്ലാ ബട്ടണുകളും വിവരങ്ങളും തത്സമയം മാറും.',
    },
    'fully_supported_langs': {
      AppLanguage.en: 'Fully Supported Languages',
      AppLanguage.hi: 'पूर्णतः समर्थित भाषाएं',
      AppLanguage.ml: 'പൂർണ്ണ പിന്തുണയുള്ള ഭാഷകൾ',
    },
    'official_langs_india': {
      AppLanguage.en: 'Official Languages of India',
      AppLanguage.hi: 'भारत की आधिकारिक भाषाएं',
      AppLanguage.ml: 'ഇന്ത്യയിലെ ഔദ്യോഗിക ഭാഷകൾ',
    },
    'official_langs_sub': {
      AppLanguage.en: 'Search from all 22 official Eighth Schedule languages of India:',
      AppLanguage.hi: 'भारत की 22 आधिकारिक 8वीं अनुसूची भाषाओं में खोजें:',
      AppLanguage.ml: 'ഇന്ത്യയിലെ 22 ഔദ്യോഗിക ഭാഷകളിൽ നിന്ന് തിരയുക:',
    },
    'search_lang_hint': {
      AppLanguage.en: 'Search language (e.g. Tamil, Kannada, Marathi)...',
      AppLanguage.hi: 'भाषा खोजें (उदा. तमिल, कन्नड़, मराठी)...',
      AppLanguage.ml: 'ഭാഷ തിരയുക (ഉദാ: തമിഴ്, കന്നഡ, മറാഠി)...',
    },

    // Community Tab
    'community_share_title': {
      AppLanguage.en: 'Share with your community',
      AppLanguage.hi: 'अपने समुदाय के साथ साझा करें',
      AppLanguage.ml: 'നിങ്ങളുടെ സമൂഹവുമായി പങ്കിടുക',
    },
    'community_share_sub': {
      AppLanguage.en: 'Post questions, start polls, offer jobs, or broadcast alerts.',
      AppLanguage.hi: 'प्रश्न पूछें, पोल शुरू करें, सेवा दें या सूचनाएं प्रसारित करें।',
      AppLanguage.ml: 'ചോദ്യങ്ങൾ ചോദിക്കുക, വോട്ടെടുപ്പ് നടത്തുക, അല്ലെങ്കിൽ അറിയിപ്പുകൾ നൽകുക.',
    },
    'btn_post': {
      AppLanguage.en: 'Post',
      AppLanguage.hi: 'पोस्ट',
      AppLanguage.ml: 'പോസ്റ്റ്',
    },
    'btn_poll': {
      AppLanguage.en: 'Poll',
      AppLanguage.hi: 'पोल',
      AppLanguage.ml: 'വോട്ടെടുപ്പ്',
    },
    'btn_job': {
      AppLanguage.en: 'Job / Service',
      AppLanguage.hi: 'कार्य / सेवा',
      AppLanguage.ml: 'ജോലി / സേവനം',
    },
    'btn_announcement': {
      AppLanguage.en: 'Announcement',
      AppLanguage.hi: 'घोषणा',
      AppLanguage.ml: 'അറിയിപ്പ്',
    },
    'neighborhood_feed': {
      AppLanguage.en: 'Neighborhood Feed',
      AppLanguage.hi: 'स्थानीय फीड',
      AppLanguage.ml: 'പ്രാദേശിക ഫീഡ്',
    },
    'no_community_posts': {
      AppLanguage.en: 'No Community Posts Yet',
      AppLanguage.hi: 'अभी कोई सामुदायिक पोस्ट नहीं है',
      AppLanguage.ml: 'പോസ്റ്റുകളൊന്നും ലഭ്യമല്ല',
    },
    'no_community_posts_sub': {
      AppLanguage.en: 'Be the first to post a question, start a poll, or announce a civic update.',
      AppLanguage.hi: 'प्रश्न पूछने, पोल शुरू करने या नागरिक सूचना देने वाले पहले व्यक्ति बनें।',
      AppLanguage.ml: 'ആദ്യമായി ഒരു ചോദ്യം ചോദിക്കൂ, അല്ലെങ്കിൽ അറിയിപ്പുകൾ നൽകൂ.',
    },

    // Pulse Tab
    'proximity_filter': {
      AppLanguage.en: 'Proximity Filter',
      AppLanguage.hi: 'दूरी फ़िल्टर',
      AppLanguage.ml: 'ദൂര പരിധി',
    },
    'radius_label': {
      AppLanguage.en: 'radius',
      AppLanguage.hi: 'दायरा',
      AppLanguage.ml: 'ചുറ്റളവ്',
    },
    'live_telemetry_within': {
      AppLanguage.en: 'Live Telemetry within',
      AppLanguage.hi: 'में लाइव टेलीमेट्री',
      AppLanguage.ml: 'തത്സമയ വിവരങ്ങൾ',
    },
    'recent_nearby_issues': {
      AppLanguage.en: 'Recent Nearby Issues',
      AppLanguage.hi: 'हाल की नजदीकी शिकायतें',
      AppLanguage.ml: 'സമീപകാല പരാതികൾ',
    },
    'view_on_map': {
      AppLanguage.en: 'View on Map',
      AppLanguage.hi: 'मानचित्र पर देखें',
      AppLanguage.ml: 'മാപ്പിൽ കാണുക',
    },
    'total_issues_recorded': {
      AppLanguage.en: 'total issues recorded',
      AppLanguage.hi: 'कुल शिकायतें दर्ज',
      AppLanguage.ml: 'പരാതികൾ രേഖപ്പെടുത്തി',
    },
    'meters_away': {
      AppLanguage.en: 'm away',
      AppLanguage.hi: 'मीटर दूर',
      AppLanguage.ml: 'മീറ്റർ അകലെ',
    },
    'km_away': {
      AppLanguage.en: 'km away',
      AppLanguage.hi: 'किमी दूर',
      AppLanguage.ml: 'കി.മീ അകലെ',
    },

    // SensorWatch HUD
    'sensorwatch_hud_title': {
      AppLanguage.en: 'SensorWatch HUD',
      AppLanguage.hi: 'सड़क सेंसर वॉच HUD',
      AppLanguage.ml: 'സെൻസർ വാച്ച് HUD',
    },
    'sensorwatch_idle': {
      AppLanguage.en: 'IDLE',
      AppLanguage.hi: 'निष्क्रिय',
      AppLanguage.ml: 'നിഷ്‌ക്രിയം',
    },
    'sensorwatch_monitoring': {
      AppLanguage.en: 'MONITORING',
      AppLanguage.hi: 'निगरानी जारी',
      AppLanguage.ml: 'നിരീക്ഷിക്കുന്നു',
    },
    'sensorwatch_captured': {
      AppLanguage.en: 'Captured',
      AppLanguage.hi: 'दर्ज',
      AppLanguage.ml: 'കണ്ടെത്തി',
    },
    'sensorwatch_impact_force': {
      AppLanguage.en: 'g Impact Force',
      AppLanguage.hi: 'g झटका बल',
      AppLanguage.ml: 'g ആഘാത തീവ്രത',
    },
    'sensorwatch_peak': {
      AppLanguage.en: 'Peak',
      AppLanguage.hi: 'अधिकतम',
      AppLanguage.ml: 'പരമാവധി',
    },
    'sensorwatch_speed': {
      AppLanguage.en: 'Speed',
      AppLanguage.hi: 'गति',
      AppLanguage.ml: 'വേഗത',
    },
    'sensorwatch_gps_fix': {
      AppLanguage.en: 'GPS Fix',
      AppLanguage.hi: 'GPS सिग्नल',
      AppLanguage.ml: 'GPS സിഗ്നൽ',
    },
    'sensorwatch_no_fix': {
      AppLanguage.en: 'No Fix',
      AppLanguage.hi: 'सिग्नल नहीं',
      AppLanguage.ml: 'സിഗ്നൽ ഇല്ല',
    },
    'sensorwatch_threshold': {
      AppLanguage.en: 'Threshold',
      AppLanguage.hi: 'सीमा',
      AppLanguage.ml: 'പരിധി',
    },
    'sensorwatch_widget_title': {
      AppLanguage.en: '1-Tap Home Screen Widget',
      AppLanguage.hi: '1-टैप होम स्क्रीन विजेट',
      AppLanguage.ml: 'ഹോം സ്ക്രീൻ വിജറ്റ്',
    },
    'sensorwatch_widget_sub': {
      AppLanguage.en: 'Start monitoring instantly with zero extra taps.',
      AppLanguage.hi: 'बिना रुकावट तुरंत निगरानी शुरू करें।',
      AppLanguage.ml: 'ഒറ്റ ടാപ്പിൽ നിരീക്ഷണം തുടങ്ങാം.',
    },
    'sensorwatch_widget_add': {
      AppLanguage.en: 'Add',
      AppLanguage.hi: 'जोड़ें',
      AppLanguage.ml: 'ചേർക്കുക',
    },
    'sensorwatch_shockwaves': {
      AppLanguage.en: 'Recorded Defect Shockwaves',
      AppLanguage.hi: 'दर्ज सड़क झटके व गड्ढे',
      AppLanguage.ml: 'രേഖപ്പെടുത്തിയ റോഡ് കുഴികൾ',
    },
    'sensorwatch_ready_title': {
      AppLanguage.en: 'Ready for Highway & Road Drives',
      AppLanguage.hi: 'सड़क यात्रा हेतु तैयार',
      AppLanguage.ml: 'യാത്രകൾക്ക് സജ്ജം',
    },
    'sensorwatch_ready_sub': {
      AppLanguage.en: 'Tap "Start Monitoring" before driving. Potholes and road jolts will be logged and verified with multi-user consensus.',
      AppLanguage.hi: 'गाड़ी चलाने से पहले "निगरानी शुरू करें" दबाएं। सड़क के गड्ढे स्वचालित रूप से दर्ज व सत्यापित होंगे।',
      AppLanguage.ml: 'ഡ്രൈവിംഗിന് മുൻപ് "നിരീക്ഷണം ആരംഭിക്കുക" ടാപ്പ് ചെയ്യുക. കുഴികൾ തത്സമയം രേഖപ്പെടുത്തും.',
    },

    // Category Grid & Selection
    'select_issue_category': {
      AppLanguage.en: 'Select Issue Category',
      AppLanguage.hi: 'समस्या श्रेणी चुनें',
      AppLanguage.ml: 'പരാതി വിഭാഗം തിരഞ്ഞെടുക്കുക',
    },
    'search_categories_hint': {
      AppLanguage.en: 'Search categories (e.g. pothole, light, drain)...',
      AppLanguage.hi: 'श्रेणी खोजें (उदा. गड्ढा, लाइट, नाली)...',
      AppLanguage.ml: 'വിഭാഗങ്ങൾ തിരയുക (ഉദാ: റോഡിലെ കുഴി, ലൈറ്റ്)...',
    },

    // Report Form
    'report_details': {
      AppLanguage.en: 'Report Details',
      AppLanguage.hi: 'शिकायत विवरण',
      AppLanguage.ml: 'പരാതി വിവരങ്ങൾ',
    },
    'change': {
      AppLanguage.en: 'Change',
      AppLanguage.hi: 'बदलें',
      AppLanguage.ml: 'മാറ്റുക',
    },
    'sec_issue_details': {
      AppLanguage.en: '1. Issue Details',
      AppLanguage.hi: '1. समस्या का विवरण',
      AppLanguage.ml: '1. പരാതിയുടെ വിവരങ്ങൾ',
    },
    'title_optional': {
      AppLanguage.en: 'Title (optional)',
      AppLanguage.hi: 'शीर्षक (वैकल्पिक)',
      AppLanguage.ml: 'വിഷയം (ഐച്ഛികം)',
    },
    'description_req': {
      AppLanguage.en: 'Description *',
      AppLanguage.hi: 'विवरण *',
      AppLanguage.ml: 'വിശദ വിവരണം *',
    },
    'severity': {
      AppLanguage.en: 'Severity',
      AppLanguage.hi: 'गंभीरता (Severity)',
      AppLanguage.ml: 'തീവ്രത',
    },
    'sec_location': {
      AppLanguage.en: '2. Location',
      AppLanguage.hi: '2. स्थान',
      AppLanguage.ml: '2. സ്ഥലം',
    },
    'gps_captured': {
      AppLanguage.en: 'GPS location captured',
      AppLanguage.hi: 'GPS स्थान दर्ज',
      AppLanguage.ml: 'GPS സ്ഥാനം രേഖപ്പെടുത്തി',
    },
    'select_on_map': {
      AppLanguage.en: 'Select on map',
      AppLanguage.hi: 'मानचित्र पर चुनें',
      AppLanguage.ml: 'മാപ്പിൽ തിരഞ്ഞെടുക്കുക',
    },
    'landmark_optional': {
      AppLanguage.en: 'Landmark / address (optional)',
      AppLanguage.hi: 'लैंडमार्क / पता (वैकल्पिक)',
      AppLanguage.ml: 'വിലാസം / ലാൻഡ്മാർക്ക് (ഐച്ഛികം)',
    },
    'sec_photos': {
      AppLanguage.en: '3. Photos (optional)',
      AppLanguage.hi: '3. तस्वीरें (वैकल्पिक)',
      AppLanguage.ml: '3. ഫോട്ടോകൾ (ഐച്ഛികം)',
    },
    'add_photos': {
      AppLanguage.en: 'Add',
      AppLanguage.hi: 'जोड़ें',
      AppLanguage.ml: 'ചേർക്കുക',
    },
    'submit_report_short': {
      AppLanguage.en: 'Submit report',
      AppLanguage.hi: 'शिकायत दर्ज करें',
      AppLanguage.ml: 'പരാതി സമർപ്പിക്കുക',
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
      AppLanguage.en: 'Phone Number',
      AppLanguage.hi: 'फोन नंबर',
      AppLanguage.ml: 'ഫോൺ നമ്പർ',
    },
    'ward_neighborhood': {
      AppLanguage.en: 'Ward / Area',
      AppLanguage.hi: 'वार्ड / क्षेत्र',
      AppLanguage.ml: 'വാർഡ് / പ്രദേശം',
    },
    'submit_application': {
      AppLanguage.en: 'Submit Application',
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

    // Statuses
    'status_submitted': {
      AppLanguage.en: 'Submitted',
      AppLanguage.hi: 'दर्ज',
      AppLanguage.ml: 'രേഖപ്പെടുത്തി',
    },
    'status_acknowledged': {
      AppLanguage.en: 'Acknowledged',
      AppLanguage.hi: 'स्वीकृत',
      AppLanguage.ml: 'സ്വീകരിച്ചു',
    },
    'status_in_progress': {
      AppLanguage.en: 'In Progress',
      AppLanguage.hi: 'प्रगति पर',
      AppLanguage.ml: 'നടപടിയിൽ',
    },
    'status_resolved': {
      AppLanguage.en: 'Resolved',
      AppLanguage.hi: 'समाधानित',
      AppLanguage.ml: 'പരിഹരിച്ചു',
    },
    'status_closed': {
      AppLanguage.en: 'Closed',
      AppLanguage.hi: 'बंद',
      AppLanguage.ml: 'പൂർത്തിയായി',
    },
    'status_duplicate': {
      AppLanguage.en: 'Duplicate',
      AppLanguage.hi: 'समान',
      AppLanguage.ml: 'മറ്റൊരു പരാതിയുണ്ട്',
    },

    // Severities
    'sev_low': {
      AppLanguage.en: 'Low',
      AppLanguage.hi: 'कम',
      AppLanguage.ml: 'കുറഞ്ഞത്',
    },
    'sev_medium': {
      AppLanguage.en: 'Medium',
      AppLanguage.hi: 'मध्यम',
      AppLanguage.ml: 'ഇടത്തരം',
    },
    'sev_high': {
      AppLanguage.en: 'High',
      AppLanguage.hi: 'उच्च',
      AppLanguage.ml: 'കൂടിയത്',
    },
    'sev_emergency': {
      AppLanguage.en: 'Emergency',
      AppLanguage.hi: 'आपातकालीन',
      AppLanguage.ml: 'അടിയന്തിരം',
    },

    // Categories
    'cat_pothole': {
      AppLanguage.en: 'Pothole',
      AppLanguage.hi: 'सड़क का गड्ढा',
      AppLanguage.ml: 'റോഡിലെ കുഴി',
    },
    'cat_brokenFootpath': {
      AppLanguage.en: 'Broken Footpath',
      AppLanguage.hi: 'टूटा फुटपाथ',
      AppLanguage.ml: 'തകർന്ന നടപ്പാത',
    },
    'cat_openManhole': {
      AppLanguage.en: 'Open Manhole',
      AppLanguage.hi: 'खुला मैनहोल',
      AppLanguage.ml: 'തുറന്ന മാൻഹോൾ',
    },
    'cat_fallenTree': {
      AppLanguage.en: 'Fallen Tree',
      AppLanguage.hi: 'गिरा हुआ पेड़',
      AppLanguage.ml: 'വീണ മരം',
    },
    'cat_waterlogging': {
      AppLanguage.en: 'Waterlogging',
      AppLanguage.hi: 'जलभराव',
      AppLanguage.ml: 'വെള്ളക്കെട്ട്',
    },
    'cat_roadSign': {
      AppLanguage.en: 'Road Sign',
      AppLanguage.hi: 'सड़क संकेत',
      AppLanguage.ml: 'റോഡ് സൈൻ ബോർഡ്',
    },
    'cat_garbage': {
      AppLanguage.en: 'Garbage',
      AppLanguage.hi: 'कचरा',
      AppLanguage.ml: 'മാലിന്യം',
    },
    'cat_blockedDrain': {
      AppLanguage.en: 'Blocked Drain',
      AppLanguage.hi: 'अवरुद्ध नाली',
      AppLanguage.ml: 'തടസ്സപ്പെട്ട ഓട',
    },
    'cat_sewage': {
      AppLanguage.en: 'Sewage',
      AppLanguage.hi: 'सीवेज',
      AppLanguage.ml: 'മലിനജലം',
    },
    'cat_streetLight': {
      AppLanguage.en: 'Street Light',
      AppLanguage.hi: 'स्ट्रीट लाइट',
      AppLanguage.ml: 'തെരുവ് വിളക്ക്',
    },
    'cat_damagedPole': {
      AppLanguage.en: 'Damaged Pole',
      AppLanguage.hi: 'क्षतिग्रस्त खंभा',
      AppLanguage.ml: 'തകർന്ന പോസ്റ്റ്',
    },
    'cat_powerIssue': {
      AppLanguage.en: 'Power Issue',
      AppLanguage.hi: 'बिजली समस्या',
      AppLanguage.ml: 'വൈദ്യുതി തടസ്സം',
    },
    'cat_waterSupply': {
      AppLanguage.en: 'Water Supply',
      AppLanguage.hi: 'जल आपूर्ति',
      AppLanguage.ml: 'കുടിവെള്ള വിതരണം',
    },
    'cat_pipeLeak': {
      AppLanguage.en: 'Pipe Leak',
      AppLanguage.hi: 'पाइप रिसाव',
      AppLanguage.ml: 'പൈപ്പ് ചോർച്ച',
    },
    'cat_encroachment': {
      AppLanguage.en: 'Encroachment',
      AppLanguage.hi: 'अतिक्रमण',
      AppLanguage.ml: 'കയ്യേറ്റം',
    },
    'cat_brokenProperty': {
      AppLanguage.en: 'Broken Property',
      AppLanguage.hi: 'सार्वजनिक संपत्ति क्षति',
      AppLanguage.ml: 'പൊതുമുതൽ നാശനഷ്ടം',
    },
    'cat_strayAnimals': {
      AppLanguage.en: 'Stray Animals',
      AppLanguage.hi: 'आवारा पशु',
      AppLanguage.ml: 'തെരുവ് മൃഗങ്ങൾ',
    },
    'cat_noise': {
      AppLanguage.en: 'Noise Pollution',
      AppLanguage.hi: 'ध्वनि प्रदूषण',
      AppLanguage.ml: 'ശബ്ദ മലിനീകരണം',
    },
    'cat_other': {
      AppLanguage.en: 'Other',
      AppLanguage.hi: 'अन्य',
      AppLanguage.ml: 'മറ്റുള്ളവ',
    },

    // Accessibility
    'a11y_vision_title': {
      AppLanguage.en: 'Vision & Display',
      AppLanguage.hi: 'दृष्टि एवं प्रदर्शन',
      AppLanguage.ml: 'കാഴ്ചയും പ്രദർശനവും',
    },
    'a11y_vision_sub': {
      AppLanguage.en: 'Text scaling, high contrast colours, and colour correction',
      AppLanguage.hi: 'टेक्स्ट स्केलिंग, उच्च कंट्रास्ट रंग एवं रंग सुधार',
      AppLanguage.ml: 'ടെക്സ്റ്റ് വലുപ്പം, ഉയർന്ന ദൃശ്യതീവ്രത, കളർ കറക്ഷൻ',
    },
    'a11y_text_size': {
      AppLanguage.en: 'Text size',
      AppLanguage.hi: 'अक्षर आकार',
      AppLanguage.ml: 'അക്ഷര വലിപ്പം',
    },
    'a11y_high_contrast': {
      AppLanguage.en: 'High contrast colours',
      AppLanguage.hi: 'उच्च कंट्रास्ट रंग',
      AppLanguage.ml: 'ഉയർന്ന ദൃശ്യതീവ്രതയുള്ള നിറങ്ങൾ',
    },
    'a11y_high_contrast_sub': {
      AppLanguage.en: 'Enforces solid backgrounds and high-visibility borders for maximum readability',
      AppLanguage.hi: 'अधिक स्पष्टता के लिए ठोस पृष्ठभूमि और स्पष्ट बॉर्डर लागू करता है',
      AppLanguage.ml: 'മെച്ചപ്പെട്ട വായനാസുഖത്തിനായി തെളിഞ്ഞ അരികുകളും കട്ടിയുള്ള പശ്ചാത്തലവും നൽകുന്നു',
    },
    'a11y_color_correction': {
      AppLanguage.en: 'Colour correction',
      AppLanguage.hi: 'रंग सुधार',
      AppLanguage.ml: 'കളർ കറക്ഷൻ',
    },
    'a11y_color_correction_sub': {
      AppLanguage.en: 'Adjust colours for colour vision deficiency assistance',
      AppLanguage.hi: 'वर्णान्धता सहायता के लिए रंग समायोजित करें',
      AppLanguage.ml: 'വർണ്ണാന്ധതയുള്ളവർക്ക് അനുയോജ്യമായ നിറങ്ങൾ ക്രമീകരിക്കുക',
    },
    'a11y_color_off': {
      AppLanguage.en: 'Off',
      AppLanguage.hi: 'बंद',
      AppLanguage.ml: 'ഓഫ്',
    },
    'a11y_color_deuteranomaly': {
      AppLanguage.en: 'Red-green (green weak)',
      AppLanguage.hi: 'लाल-हरा (हरा कमजोर)',
      AppLanguage.ml: 'ചുവപ്പ്-പച്ച (പച്ച കുറവ്)',
    },
    'a11y_color_protanomaly': {
      AppLanguage.en: 'Red-green (red weak)',
      AppLanguage.hi: 'लाल-हरा (लाल कमजोर)',
      AppLanguage.ml: 'ചുവപ്പ്-പച്ച (ചുവപ്പ് കുറവ്)',
    },
    'a11y_color_tritanomaly': {
      AppLanguage.en: 'Blue-yellow (tritanomaly)',
      AppLanguage.hi: 'नीला-पीला (ट्राइटनॉमली)',
      AppLanguage.ml: 'നീല-മഞ്ഞ (ട്രിറ്റനോമലി)',
    },
    'a11y_color_greyscale': {
      AppLanguage.en: 'Greyscale',
      AppLanguage.hi: 'ग्रेस्केल',
      AppLanguage.ml: 'ഗ്രേസ്കെയിൽ',
    },
    'a11y_motion_title': {
      AppLanguage.en: 'Motion & Animations',
      AppLanguage.hi: 'गति एवं एनिमेशन',
      AppLanguage.ml: 'ചലനവും ആനിമേഷനുകളും',
    },
    'a11y_motion_sub': {
      AppLanguage.en: 'Control dynamic transforms and spring physics',
      AppLanguage.hi: 'डायनामिक ट्रांसफॉर्म और स्प्रिंग फिजिक्स नियंत्रित करें',
      AppLanguage.ml: 'ആനിമേഷനുകളും സ്പ്രിംഗ് ഇഫക്റ്റുകളും നിയന്ത്രിക്കുക',
    },
    'a11y_remove_animations': {
      AppLanguage.en: 'Remove animations',
      AppLanguage.hi: 'एनिमेशन हटाएं',
      AppLanguage.ml: 'ആനിമേഷനുകൾ ഒഴിവാക്കുക',
    },
    'a11y_remove_animations_sub': {
      AppLanguage.en: 'Remove user interface animations and transitions',
      AppLanguage.hi: 'यूज़र इंटरफ़ेस एनिमेशन और ट्रांज़िशन हटाएं',
      AppLanguage.ml: 'യൂസർ ഇന്റർഫേസ് ആനിമേഷനുകൾ പൂർണ്ണമായി ഒഴിവാക്കുക',
    },
    'a11y_interaction_title': {
      AppLanguage.en: 'Interaction & Touch',
      AppLanguage.hi: 'संवाद एवं स्पर्श',
      AppLanguage.ml: 'ടച്ച് ക്രമീകരണങ്ങൾ',
    },
    'a11y_interaction_sub': {
      AppLanguage.en: 'Haptic feedback and tap debounce timings',
      AppLanguage.hi: 'हैप्टिक फीडबैक एवं टैप टाइमिंग',
      AppLanguage.ml: 'ഹാപ്റ്റിക് ഫീഡ്‌ബാക്കും ടച്ച് സമയക്രമീകരണങ്ങളും',
    },
    'a11y_haptics': {
      AppLanguage.en: 'Haptic feedback',
      AppLanguage.hi: 'हैप्टिक फीडबैक',
      AppLanguage.ml: 'ഹാപ്റ്റിക് ഫീഡ്‌ബാക്ക്',
    },
    'a11y_haptics_sub': {
      AppLanguage.en: 'Vibrate on button presses, navigation, and impact detections',
      AppLanguage.hi: 'बटन दबाने, नेविगेशन और प्रभाव पहचान पर कंपन करें',
      AppLanguage.ml: 'ബട്ടൺ അമർത്തുമ്പോഴും വഴികാട്ടുമ്പോഴും വൈബ്രേഷൻ നൽകുക',
    },
    'a11y_ignore_repeated': {
      AppLanguage.en: 'Ignore repeated taps',
      AppLanguage.hi: 'बार-बार टैप अनदेखा करें',
      AppLanguage.ml: 'ആവർത്തിച്ചുള്ള ടച്ചുകൾ അവഗണിക്കുക',
    },
    'a11y_ignore_repeated_sub': {
      AppLanguage.en: 'Treat multiple rapid taps as a single tap to prevent accidental triggers',
      AppLanguage.hi: 'गलती से होने वाले टैप से बचने के लिए लगातार कई टैप को एक मानें',
      AppLanguage.ml: 'വേഗത്തിൽ ഒന്നിലധികം തവണ അമർത്തുന്നത് ഒറ്റ ടച്ചായി കണക്കാക്കുക',
    },
    'a11y_tap_duration': {
      AppLanguage.en: 'Tap debounce duration',
      AppLanguage.hi: 'टैप अंतराल अवधि',
      AppLanguage.ml: 'ടച്ച് കാലതാമസ സമയം',
    },
    'a11y_voice_title': {
      AppLanguage.en: 'Voice Alerts',
      AppLanguage.hi: 'ध्वनि सूचनाएं',
      AppLanguage.ml: 'വോയ്സ് അലേർട്ടുകൾ',
    },
    'a11y_voice_sub': {
      AppLanguage.en: 'Internal speech alerts via device speaker',
      AppLanguage.hi: 'डिवाइस स्पीकर के माध्यम से आंतरिक ध्वनि सूचनाएं',
      AppLanguage.ml: 'ഫോൺ സ്പീക്കറിലൂടെയുള്ള ശബ്ദ അറിയിപ്പുകൾ',
    },
    'a11y_voice_alerts': {
      AppLanguage.en: 'Speak alerts',
      AppLanguage.hi: 'अलर्ट बोलें',
      AppLanguage.ml: 'ശബ്ദത്തിൽ അറിയിക്കുക',
    },
    'a11y_voice_alerts_sub': {
      AppLanguage.en: 'Announce road events and status updates through device speaker',
      AppLanguage.hi: 'डिवाइस स्पीकर के माध्यम से सड़क की घटनाओं और स्थिति अपडेट की घोषणा करें',
      AppLanguage.ml: 'റോഡ് വിവരങ്ങളും സ്റ്റാറ്റസ് മാറ്റങ്ങളും സ്പീക്കറിലൂടെ വിളിച്ചുപറയുക',
    },
  };

  /// Translate a string key for a given language.
  static String tr(String key, AppLanguage lang) {
    final entry = _dict[key];
    if (entry == null) return key;
    return entry[lang] ?? entry[AppLanguage.en] ?? key;
  }

  /// Translate category name
  static String categoryName(ReportCategory category, AppLanguage lang) {
    return tr('cat_${category.name}', lang);
  }

  /// Translate severity name
  static String severityName(Severity severity, AppLanguage lang) {
    return tr('sev_${severity.name}', lang);
  }

  /// Translate status name
  static String statusName(ReportStatus status, AppLanguage lang) {
    return tr('status_${status.wire.toLowerCase()}', lang);
  }

  /// Translate role name
  static String roleName(UserRole role, AppLanguage lang) {
    return tr('role_${role.name}', lang);
  }
}
