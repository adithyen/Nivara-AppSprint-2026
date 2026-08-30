import 'package:flutter/material.dart';

/// The civic-impact ladder: ten community-help ranks a citizen climbs as their
/// activity score grows. Points are the derived civic score
/// (reports×10 + confirms×5 + finds×15) computed on Home/Profile — this maps
/// that number onto a named level and the progress toward the next one.
///
/// Purely a function of the score, so it never needs its own storage.
@immutable
class CivicLevel {
  const CivicLevel({
    required this.rank,
    required this.name,
    required this.blurb,
    required this.icon,
    required this.color,
    required this.floor,
    required this.nextFloor,
  });

  /// 1‥10.
  final int rank;
  final String name;

  /// A short flavour line shown under the rank.
  final String blurb;
  final IconData icon;
  final Color color;

  /// Minimum points to hold this rank.
  final int floor;

  /// Minimum points for the next rank, or null at the top of the ladder.
  final int? nextFloor;

  bool get isMax => nextFloor == null;

  String localizedName(dynamic lang) {
    final langCode = lang.toString().split('.').last;
    if (langCode == 'ml') {
      return switch (rank) {
        1 => 'നല്ല അയൽവാസി',
        2 => 'തെരുവ് സംരക്ഷകൻ',
        3 => 'വാർഡ് നിരീക്ഷകൻ',
        4 => 'വാർഡ് ഗാർഡിയൻ',
        5 => 'പൗര സ്കൗട്ട്',
        6 => 'സമൂഹ നായകൻ',
        7 => 'നഗര കാവലാൾ',
        8 => 'വികസന മുന്നണി',
        9 => 'പൗര പ്രമുഖൻ',
        _ => 'നിവാര ലെജൻഡ്',
      };
    } else if (langCode == 'hi') {
      return switch (rank) {
        1 => 'सच्चा पड़ोसी',
        2 => 'सड़क संरक्षक',
        3 => 'ब्लॉक प्रहरी',
        4 => 'वार्ड रक्षक',
        5 => 'नागरिक स्काउट',
        6 => 'सामुदायिक चैंपियन',
        7 => 'नगर प्रहरी',
        8 => 'शहरी मार्गदर्शक',
        9 => 'नागरिक प्रकाश स्तंभ',
        _ => 'निवारा लीजेंड',
      };
    }
    return name;
  }

  String localizedBlurb(dynamic lang) {
    final langCode = lang.toString().split('.').last;
    if (langCode == 'ml') {
      return switch (rank) {
        1 => 'ഒരു നല്ല അയൽവാസിയിൽ നിന്നാണ് തുടക്കം.',
        2 => 'നിങ്ങളുടെ തെരുവിനെ നിരീക്ഷിക്കുന്നു.',
        3 => 'സമീപ പ്രദേശങ്ങളിൽ ജാഗ്രത.',
        4 => 'വാർഡിന്റെ സജീവ ശബ്ദം.',
        5 => 'നഗര പ്രശ്നങ്ങൾ കണ്ടെത്തുന്നു.',
        6 => 'നാടിനെ ഒന്നിപ്പിച്ച് നയിക്കുന്നു.',
        7 => 'നഗര സുരക്ഷയ്ക്കും സേവനത്തിനും മുന്നിൽ.',
        8 => 'പൗര മാറ്റങ്ങൾക്ക് നേതൃത്വം നൽകുന്നു.',
        9 => 'നഗരത്തിന് മാതൃകയായ വ്യക്തിത്വം.',
        _ => 'നിങ്ങൾ ഉള്ളതുകൊണ്ട് നഗരം കൂടുതൽ മികച്ചതാകുന്നു.',
      };
    } else if (langCode == 'hi') {
      return switch (rank) {
        1 => 'हर शहर की शुरुआत यहीं से होती है।',
        2 => 'अपनी सड़क की देखभाल।',
        3 => 'पड़ोस पर सतर्क नजर।',
        4 => 'वार्ड के लिए एक मजबूत आवाज।',
        5 => 'समस्याओं की पहचान में आगे।',
        6 => 'पूरे इलाके को एकजुट करना।',
        7 => 'शहर की सुरक्षा और स्वच्छता।',
        8 => 'नागरिक बदलाव का नेतृत्व।',
        9 => 'शहर के लिए एक प्रेरणादायक उदाहरण।',
        _ => 'आपके सहयोग से शहर बेहतर बनता है।',
      };
    }
    return blurb;
  }
}

/// A citizen's position on the ladder: their level plus live progress numbers.
@immutable
class CivicStanding {
  const CivicStanding({required this.level, required this.points});

  final CivicLevel level;
  final int points;

  /// Points earned within the current band.
  int get pointsIntoLevel => (points - level.floor).clamp(0, 1 << 30);

  /// Band width (points from this level's floor to the next).
  int get bandSize => level.isMax ? 0 : level.nextFloor! - level.floor;

  /// Points still needed to reach the next rank (0 at max).
  int get pointsToNext =>
      level.isMax ? 0 : (level.nextFloor! - points).clamp(0, 1 << 30);

  /// 0‥1 fill of the current band (1.0 at max rank).
  double get progress {
    if (level.isMax || bandSize <= 0) return 1;
    return (pointsIntoLevel / bandSize).clamp(0.0, 1.0);
  }
}

/// The ladder, ascending. Floors are chosen so the first rank-ups come quickly
/// (a few reports) and later ranks take sustained contribution.
const List<_LevelSpec> _kLadder = [
  _LevelSpec(
    1,
    'Good Neighbour',
    'Every city starts with one.',
    Icons.handshake,
    0xFF7F8C8D,
    0,
  ),
  _LevelSpec(
    2,
    'Street Steward',
    'Looking out for your street.',
    Icons.cleaning_services,
    0xFF16A085,
    30,
  ),
  _LevelSpec(
    3,
    'Block Watcher',
    'Eyes on the neighbourhood.',
    Icons.visibility,
    0xFF27AE60,
    80,
  ),
  _LevelSpec(
    4,
    'Ward Guardian',
    'A voice for your ward.',
    Icons.shield,
    0xFF2980B9,
    150,
  ),
  _LevelSpec(
    5,
    'Civic Scout',
    'Always finding what needs fixing.',
    Icons.explore,
    0xFF1B6CA8,
    260,
  ),
  _LevelSpec(
    6,
    'Community Champion',
    'Rallying the whole locality.',
    Icons.emoji_events,
    0xFF8E44AD,
    420,
  ),
  _LevelSpec(
    7,
    'City Sentinel',
    'Standing guard over the city.',
    Icons.location_city,
    0xFFD35400,
    650,
  ),
  _LevelSpec(
    8,
    'Urban Vanguard',
    'Leading civic change from the front.',
    Icons.bolt,
    0xFFE67E22,
    950,
  ),
  _LevelSpec(
    9,
    'Civic Luminary',
    'An example the city looks up to.',
    Icons.auto_awesome,
    0xFFF5A623,
    1400,
  ),
  _LevelSpec(
    10,
    'Nivara Legend',
    'The city runs better because of you.',
    Icons.workspace_premium,
    0xFFD4AC0D,
    2000,
  ),
];

/// Resolve a points total to the citizen's current standing.
CivicStanding civicStandingFor(int points) {
  final p = points < 0 ? 0 : points;
  var idx = 0;
  for (var i = 0; i < _kLadder.length; i++) {
    if (p >= _kLadder[i].floor) idx = i;
  }
  final spec = _kLadder[idx];
  final next = idx + 1 < _kLadder.length ? _kLadder[idx + 1].floor : null;
  return CivicStanding(
    level: CivicLevel(
      rank: spec.rank,
      name: spec.name,
      blurb: spec.blurb,
      icon: spec.icon,
      color: Color(spec.colorValue),
      floor: spec.floor,
      nextFloor: next,
    ),
    points: p,
  );
}

/// The full ladder as [CivicLevel]s — for a "how levels work" reference view.
List<CivicLevel> civicLadder() => [
  for (var i = 0; i < _kLadder.length; i++)
    CivicLevel(
      rank: _kLadder[i].rank,
      name: _kLadder[i].name,
      blurb: _kLadder[i].blurb,
      icon: _kLadder[i].icon,
      color: Color(_kLadder[i].colorValue),
      floor: _kLadder[i].floor,
      nextFloor: i + 1 < _kLadder.length ? _kLadder[i + 1].floor : null,
    ),
];

/// Compact internal ladder entry (kept const-friendly with an int colour).
class _LevelSpec {
  const _LevelSpec(
    this.rank,
    this.name,
    this.blurb,
    this.icon,
    this.colorValue,
    this.floor,
  );
  final int rank;
  final String name;
  final String blurb;
  final IconData icon;
  final int colorValue;
  final int floor;
}
