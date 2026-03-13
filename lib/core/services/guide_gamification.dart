// Guide Gamification Service
// Calculates XP, levels, and badges from Firestore data
// 100-level progression system with unique titles

import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';

// ============================================
// LEVEL DEFINITIONS — 100 LEVELS
// ============================================

class GuideLevel {
  final int level;
  final String title;
  final String badge;
  final int xpRequired;

  const GuideLevel({
    required this.level,
    required this.title,
    required this.badge,
    required this.xpRequired,
  });
}

/// All 100 levels with hand-crafted titles and a smooth XP curve.
/// Early levels come fast (~50-150 XP each), later levels slow down.
final List<GuideLevel> guideLevels = _buildLevels();

List<GuideLevel> _buildLevels() {
  // Title + emoji for each level (1-100)
  const data = <List<String>>[
    // --- TIER 1: NEWCOMER (1-10) ---
    ['Newcomer',         '🌱'],  // 1
    ['Rookie',           '🐣'],  // 2
    ['Greenhorn',        '🌿'],  // 3
    ['Apprentice',       '📖'],  // 4
    ['Night Walker',     '🚶'],  // 5
    ['Sky Watcher',      '👁️'],  // 6
    ['Stargazer',        '⭐'],  // 7
    ['Moon Chaser',      '🌙'],  // 8
    ['Frost Scout',      '❄️'],  // 9
    ['Trailblazer',      '🥾'],  // 10
    // --- TIER 2: EXPLORER (11-20) ---
    ['Explorer',         '🧭'],  // 11
    ['Wayfinder',        '🗺️'],  // 12
    ['Dusk Ranger',      '🌅'],  // 13
    ['Ice Trekker',      '🏔️'],  // 14
    ['Storm Watcher',    '🌧️'],  // 15
    ['Horizon Seeker',   '🔭'],  // 16
    ['Pathfinder',       '🛤️'],  // 17
    ['Night Owl',        '🦉'],  // 18
    ['Polar Wanderer',   '🐧'],  // 19
    ['Arctic Fox',       '🦊'],  // 20
    // --- TIER 3: HUNTER (21-35) ---
    ['Aurora Spotter',   '👀'],  // 21
    ['Light Seeker',     '🔦'],  // 22
    ['Glow Chaser',      '✨'],  // 23
    ['Aurora Apprentice', '🌠'],  // 24
    ['Night Rider',      '🏇'],  // 25
    ['Beacon Finder',    '🏮'],  // 26
    ['Fjord Runner',     '🌊'],  // 27
    ['Glacier Guide',    '🧊'],  // 28
    ['Snow Tracker',     '🐾'],  // 29
    ['Lava Walker',      '🌋'],  // 30
    ['Wild Scout',       '🐺'],  // 31
    ['Thunder Watcher',  '⛈️'],  // 32
    ['Aurora Hunter',    '🌌'],  // 33
    ['Tide Reader',      '🌊'],  // 34
    ['Rune Seeker',      '🔮'],  // 35
    // --- TIER 4: VETERAN (36-50) ---
    ['Veteran',          '🎖️'],  // 36
    ['Iron Will',        '⚙️'],  // 37
    ['Storm Rider',      '🌪️'],  // 38
    ['Flame Keeper',     '🕯️'],  // 39
    ['Shield Bearer',    '🛡️'],  // 40
    ['Wolf Guide',       '🐺'],  // 41
    ['Shadow Walker',    '🌑'],  // 42
    ['Frost Warden',     '🥶'],  // 43
    ['Midnight Sun',     '☀️'],  // 44
    ['Saga Teller',      '📜'],  // 45
    ['Mountain King',    '⛰️'],  // 46
    ['Storm Chaser',     '🌊'],  // 47
    ['Fire Watcher',     '🔥'],  // 48
    ['Dawn Breaker',     '🌤️'],  // 49
    ['Half Century',     '💪'],  // 50
    // --- TIER 5: ELITE (51-65) ---
    ['Elite Guide',      '💎'],  // 51
    ['Star Navigator',   '🧭'],  // 52
    ['Cosmic Tracker',   '🌐'],  // 53
    ['Nebula Scout',     '🔭'],  // 54
    ['Solar Flare',      '☄️'],  // 55
    ['Void Walker',      '🕳️'],  // 56
    ['Aurora Ace',       '🃏'],  // 57
    ['Sky Marshal',      '🎯'],  // 58
    ['Polar Commander',  '🏴'],  // 59
    ['Thunder Lord',     '⚡'],  // 60
    ['Ice Commander',    '🏔️'],  // 61
    ['Eagle Eye',        '🦅'],  // 62
    ['Aurora Knight',    '⚔️'],  // 63
    ['Night Commander',  '🌃'],  // 64
    ['Crown Hunter',     '👑'],  // 65
    // --- TIER 6: MASTER (66-80) ---
    ['Aurora Master',    '🎓'],  // 66
    ['Grand Pathfinder', '🗺️'],  // 67
    ['Dragon Rider',     '🐉'],  // 68
    ['Frost Monarch',    '❄️'],  // 69
    ['Seventy Strong',   '🏋️'],  // 70
    ['Titan Guide',      '🗿'],  // 71
    ['Phantom Walker',   '👻'],  // 72
    ['Sky Shaman',       '🪬'],  // 73
    ['Rune Master',      '🔮'],  // 74
    ['Wolf King',        '🐺'],  // 75
    ['Celestial Keeper', '🌟'],  // 76
    ['Storm Sage',       '🧙'],  // 77
    ['Aurora Warden',    '🛡️'],  // 78
    ['Bifrost Walker',   '🌈'],  // 79
    ['Eighty Legend',    '🏅'],  // 80
    // --- TIER 7: LEGEND (81-90) ---
    ['Living Legend',    '🦁'],  // 81
    ['Mythic Guide',     '🏛️'],  // 82
    ['Saga Hero',        '📖'],  // 83
    ['Ragnarok Ready',   '⚒️'],  // 84
    ['Eternal Flame',    '🔥'],  // 85
    ['Frost Giant',      '🧊'],  // 86
    ['Valkyrie',         '🪽'],  // 87
    ['Einherjar',        '⚔️'],  // 88
    ['Asgard Bound',     '🌀'],  // 89
    ['Viking Legend',    '🛡️'],  // 90
    // --- TIER 8: GOD (91-100) ---
    ['Demigod',          '🔱'],  // 91
    ['Sky Father',       '⛅'],  // 92
    ['Storm God',        '🌩️'],  // 93
    ['Fenrir Slayer',    '🐲'],  // 94
    ['World Serpent',    '🐍'],  // 95
    ['Mjolnir Bearer',   '🔨'],  // 96
    ['Allfather\'s Eye', '👁️'],  // 97
    ['Valhalla Elite',   '⚔️'],  // 98
    ['Northern God',     '👑'],  // 99
    ['Odin\'s Chosen',   '🏆'],  // 100
  ];

  // XP curve: polynomial ramp — fast early, slower later
  // Formula: xp(n) = round(15 * n^1.65)
  // Lv1=0, Lv2≈47, Lv5≈200, Lv10≈670, Lv25≈3300, Lv50≈11600,
  // Lv75≈24000, Lv100≈40500
  final levels = <GuideLevel>[];
  for (int i = 0; i < data.length; i++) {
    final n = i + 1;
    final xp = n == 1 ? 0 : (15.0 * math.pow(n.toDouble(), 1.65)).round();
    levels.add(GuideLevel(
      level: n,
      title: data[i][0],
      badge: data[i][1],
      xpRequired: xp,
    ));
  }
  return levels;
}

// ============================================
// BADGE DEFINITIONS
// ============================================

class GuideBadge {
  final String id;
  final String name;
  final String emoji;
  final String description;
  final bool Function(GuideStats) isEarned;

  const GuideBadge({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.isEarned,
  });
}

final List<GuideBadge> allBadges = [
  GuideBadge(
    id: 'first_shift',
    name: 'First Shift',
    emoji: '🌟',
    description: 'Complete your first shift',
    isEarned: (s) => s.completedShifts >= 1,
  ),
  GuideBadge(
    id: 'night_5',
    name: 'Five Nights',
    emoji: '🌙',
    description: 'Complete 5 shifts',
    isEarned: (s) => s.completedShifts >= 5,
  ),
  GuideBadge(
    id: 'reliable',
    name: 'Reliable',
    emoji: '🎯',
    description: 'Complete 10 shifts',
    isEarned: (s) => s.completedShifts >= 10,
  ),
  GuideBadge(
    id: 'aurora_spotter',
    name: 'Aurora Spotter',
    emoji: '👀',
    description: 'Spot aurora on 3 tours',
    isEarned: (s) => s.auroraSightings >= 3,
  ),
  GuideBadge(
    id: 'aurora_magnet',
    name: 'Aurora Magnet',
    emoji: '🌈',
    description: 'Spot aurora on 10 tours',
    isEarned: (s) => s.auroraSightings >= 10,
  ),
  GuideBadge(
    id: 'strong_aurora',
    name: 'Storm Chaser',
    emoji: '🔥',
    description: 'Witness a strong aurora (Kp5+)',
    isEarned: (s) => s.strongAuroraSightings >= 1,
  ),
  GuideBadge(
    id: 'people_person',
    name: 'People Person',
    emoji: '👥',
    description: 'Serve 200+ passengers',
    isEarned: (s) => s.totalPassengersServed >= 200,
  ),
  GuideBadge(
    id: 'crowd_master',
    name: 'Crowd Master',
    emoji: '🏟️',
    description: 'Serve 500+ passengers',
    isEarned: (s) => s.totalPassengersServed >= 500,
  ),
  GuideBadge(
    id: 'century',
    name: 'Century',
    emoji: '💯',
    description: 'Complete 100 shifts',
    isEarned: (s) => s.completedShifts >= 100,
  ),
  GuideBadge(
    id: 'veteran',
    name: 'Veteran',
    emoji: '🏆',
    description: 'Complete 50 shifts',
    isEarned: (s) => s.completedShifts >= 50,
  ),
  GuideBadge(
    id: 'no_show_handler',
    name: 'Patience',
    emoji: '🧘',
    description: 'Handle 10+ no-shows gracefully',
    isEarned: (s) => s.noShowsHandled >= 10,
  ),
  // OG badge for early adopters
  GuideBadge(
    id: 'og_viking',
    name: 'OG Viking',
    emoji: '⚔️',
    description: 'Joined Aurora Viking in its founding era (2026 or earlier)',
    isEarned: (s) => s.isOG,
  ),
];

// ============================================
// GUIDE STATS MODEL
// ============================================

class GuideStats {
  final String guideId;
  final String guideName;
  final int completedShifts;
  final int auroraSightings;
  final int strongAuroraSightings;
  final int totalPassengersServed;
  final int noShowsHandled;
  final int totalXP;
  final GuideLevel currentLevel;
  final GuideLevel? nextLevel;
  final double levelProgress; // 0.0 - 1.0
  final List<GuideBadge> earnedBadges;
  final bool isOG;      // Joined 2026 or before
  final bool isAdmin;   // Admin user

  const GuideStats({
    required this.guideId,
    required this.guideName,
    required this.completedShifts,
    required this.auroraSightings,
    required this.strongAuroraSightings,
    required this.totalPassengersServed,
    required this.noShowsHandled,
    required this.totalXP,
    required this.currentLevel,
    this.nextLevel,
    required this.levelProgress,
    required this.earnedBadges,
    this.isOG = false,
    this.isAdmin = false,
  });

  /// Display title that accounts for OG status and admin status.
  /// Admins at max level get a special endgame title.
  /// OG guides get a prefix.
  String get displayTitle {
    if (isAdmin && currentLevel.level >= 90) {
      return '🏛️ Allfather';
    }
    if (isOG) {
      return '⚔️ OG ${currentLevel.title}';
    }
    return currentLevel.title;
  }

  String get displayBadge {
    if (isAdmin && currentLevel.level >= 90) {
      return '🏛️';
    }
    if (isOG) {
      return '⚔️';
    }
    return currentLevel.badge;
  }
}

// ============================================
// GAMIFICATION SERVICE
// ============================================

class GuideGamificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Calculate full guide stats from Firestore data
  Future<GuideStats> calculateGuideStats(String guideId, {String? guideName}) async {
    int completedShifts = 0;
    int auroraSightings = 0;
    int strongAuroraSightings = 0;
    int totalPassengersServed = 0;
    int noShowsHandled = 0;
    bool isOG = false;
    bool isAdmin = false;

    // 0. Look up user doc for createdAt and isAdmin
    try {
      final userDoc = await _firestore.collection('users').doc(guideId).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        if (data['createdAt'] != null) {
          final createdAt = DateTime.parse(data['createdAt']);
          isOG = createdAt.year <= 2026;
        }
        isAdmin = data['isAdmin'] == true;
        guideName ??= data['fullName'] as String? ?? '';
      }
    } catch (e) {
      print('⚠️ Could not load user doc: $e');
    }

    // 1. Count completed shifts
    try {
      final shiftsSnapshot = await _firestore
          .collection('shifts')
          .where('guideId', isEqualTo: guideId)
          .where('status', isEqualTo: 'completed')
          .get();
      completedShifts = shiftsSnapshot.docs.length;

      // Also count accepted shifts (currently active)
      final acceptedSnapshot = await _firestore
          .collection('shifts')
          .where('guideId', isEqualTo: guideId)
          .where('status', isEqualTo: 'accepted')
          .get();
      completedShifts += acceptedSnapshot.docs.length;
    } catch (e) {
      print('⚠️ Could not count shifts: $e');
    }

    // 2. Count aurora sightings from end-of-shift reports
    try {
      final reportsSnapshot = await _firestore
          .collection('end_of_shift_reports')
          .where('guideId', isEqualTo: guideId)
          .get();

      for (final doc in reportsSnapshot.docs) {
        final data = doc.data();
        final rating = data['auroraRating'];
        if (rating != null) {
          // Any aurora sighting (Kp 1+)
          if (rating is int && rating >= 1 || rating is double && rating >= 1) {
            auroraSightings++;
          }
          // Strong aurora (Kp 5+)
          if (rating is int && rating >= 5 || rating is double && rating >= 5) {
            strongAuroraSightings++;
          }
        }
      }
    } catch (e) {
      print('⚠️ Could not count aurora sightings: $e');
    }

    // 3. Count passengers served from pickup_assignments
    try {
      final assignmentsSnapshot = await _firestore
          .collection('pickup_assignments')
          .where('guideId', isEqualTo: guideId)
          .get();

      for (final doc in assignmentsSnapshot.docs) {
        final data = doc.data();
        if (data['totalPassengers'] != null) {
          totalPassengersServed += (data['totalPassengers'] as int?) ?? 0;
        } else if (data['bookings'] != null && data['bookings'] is List) {
          final bookings = data['bookings'] as List;
          for (final booking in bookings) {
            totalPassengersServed += (booking['numberOfGuests'] as int?) ?? 0;
          }
        }
      }
    } catch (e) {
      print('⚠️ Could not count passengers: $e');
    }

    // 4. Count no-shows handled from booking_status
    try {
      final noShowSnapshot = await _firestore
          .collection('booking_status')
          .where('guideId', isEqualTo: guideId)
          .where('isNoShow', isEqualTo: true)
          .get();
      noShowsHandled = noShowSnapshot.docs.length;
    } catch (e) {
      print('⚠️ Could not count no-shows: $e');
    }

    // 5. Calculate XP
    int xp = 0;
    xp += completedShifts * 100;        // 100 XP per shift
    xp += auroraSightings * 50;          // 50 XP per aurora
    xp += strongAuroraSightings * 100;   // 100 bonus for strong aurora (150 total)
    xp += totalPassengersServed * 5;     // 5 XP per passenger
    xp += noShowsHandled * 10;           // 10 XP per no-show handled

    // 6. Calculate level
    final levelInfo = getLevelInfo(xp);

    // 7. Calculate badges
    final tempStats = GuideStats(
      guideId: guideId,
      guideName: guideName ?? '',
      completedShifts: completedShifts,
      auroraSightings: auroraSightings,
      strongAuroraSightings: strongAuroraSightings,
      totalPassengersServed: totalPassengersServed,
      noShowsHandled: noShowsHandled,
      totalXP: xp,
      currentLevel: levelInfo['current'] as GuideLevel,
      nextLevel: levelInfo['next'] as GuideLevel?,
      levelProgress: levelInfo['progress'] as double,
      earnedBadges: [],
      isOG: isOG,
      isAdmin: isAdmin,
    );

    final earnedBadges = allBadges.where((badge) => badge.isEarned(tempStats)).toList();

    return GuideStats(
      guideId: guideId,
      guideName: guideName ?? '',
      completedShifts: completedShifts,
      auroraSightings: auroraSightings,
      strongAuroraSightings: strongAuroraSightings,
      totalPassengersServed: totalPassengersServed,
      noShowsHandled: noShowsHandled,
      totalXP: xp,
      currentLevel: levelInfo['current'] as GuideLevel,
      nextLevel: levelInfo['next'] as GuideLevel?,
      levelProgress: levelInfo['progress'] as double,
      earnedBadges: earnedBadges,
      isOG: isOG,
      isAdmin: isAdmin,
    );
  }

  /// Get level info from XP
  static Map<String, dynamic> getLevelInfo(int xp) {
    GuideLevel current = guideLevels.first;
    GuideLevel? next;

    for (int i = 0; i < guideLevels.length; i++) {
      if (xp >= guideLevels[i].xpRequired) {
        current = guideLevels[i];
        next = i + 1 < guideLevels.length ? guideLevels[i + 1] : null;
      }
    }

    double progress = 0.0;
    if (next != null) {
      final xpInLevel = xp - current.xpRequired;
      final xpForNextLevel = next.xpRequired - current.xpRequired;
      progress = xpForNextLevel > 0 ? (xpInLevel / xpForNextLevel).clamp(0.0, 1.0) : 1.0;
    } else {
      progress = 1.0; // Max level
    }

    return {
      'current': current,
      'next': next,
      'progress': progress,
    };
  }
}
