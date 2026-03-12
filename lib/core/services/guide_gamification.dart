// Guide Gamification Service
// Calculates XP, levels, and badges from Firestore data

import 'package:cloud_firestore/cloud_firestore.dart';

// ============================================
// LEVEL DEFINITIONS
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

const List<GuideLevel> guideLevels = [
  GuideLevel(level: 1, title: 'Rookie', badge: '🌱', xpRequired: 0),
  GuideLevel(level: 2, title: 'Explorer', badge: '🧭', xpRequired: 300),
  GuideLevel(level: 3, title: 'Pathfinder', badge: '🥾', xpRequired: 800),
  GuideLevel(level: 4, title: 'Night Owl', badge: '🦉', xpRequired: 1500),
  GuideLevel(level: 5, title: 'Stargazer', badge: '⭐', xpRequired: 3000),
  GuideLevel(level: 6, title: 'Aurora Hunter', badge: '🌌', xpRequired: 5000),
  GuideLevel(level: 7, title: 'Storm Chaser', badge: '🌊', xpRequired: 8000),
  GuideLevel(level: 8, title: 'Aurora Master', badge: '⚡', xpRequired: 12000),
  GuideLevel(level: 9, title: 'Trail Blazer', badge: '🔥', xpRequired: 18000),
  GuideLevel(level: 10, title: 'Viking Legend', badge: '🛡️', xpRequired: 25000),
  GuideLevel(level: 11, title: 'Valhalla Elite', badge: '⚔️', xpRequired: 35000),
  GuideLevel(level: 12, title: 'Northern God', badge: '👑', xpRequired: 50000),
];

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
  });
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
