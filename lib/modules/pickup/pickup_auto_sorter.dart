import '../../core/models/pickup_models.dart';
import '../../core/services/firebase_service.dart';

/// Intelligent auto-sorter for pickup lists.
///
/// Learns from historical route snapshots to determine the optimal pickup
/// order. Each time an admin manually reorders a guide's pickup list, the
/// order of pickup-place names is saved as a route snapshot. This class
/// reads those snapshots and computes a weighted average position for every
/// pickup place, then sorts bookings accordingly.
///
/// When no history exists, falls back to alphabetical grouping by pickup
/// place name.
class PickupAutoSorter {
  /// Auto-sort a single guide's booking list using historical route data.
  ///
  /// Returns a new list with the bookings sorted by learned route order.
  /// Bookings at the same pickup place are grouped together.
  static Future<List<PickupBooking>> autoSortBookings(
    List<PickupBooking> bookings,
  ) async {
    if (bookings.length <= 1) return List.from(bookings);

    // Fetch route history from ALL guides (routes are generally the same)
    final routeHistory = await FirebaseService.getPickupRouteHistory(limit: 60);

    if (routeHistory.isEmpty) {
      print('📍 No route history found — falling back to alphabetical group sort');
      return _alphabeticalGroupSort(bookings);
    }

    // Build a score map: place name → average position (lower = earlier in route)
    final positionScores = _buildPositionScores(routeHistory);

    print('📍 Built position scores for ${positionScores.length} pickup places from ${routeHistory.length} snapshots');

    return _sortByScores(bookings, positionScores);
  }

  /// Auto-sort every guide's list in the provided guide lists.
  static Future<Map<String, List<PickupBooking>>> autoSortAllGuides(
    List<GuidePickupList> guideLists,
  ) async {
    // Fetch history once and reuse for all guides
    final routeHistory = await FirebaseService.getPickupRouteHistory(limit: 60);
    final positionScores = routeHistory.isNotEmpty
        ? _buildPositionScores(routeHistory)
        : <String, double>{};

    final results = <String, List<PickupBooking>>{};

    for (final guideList in guideLists) {
      if (guideList.bookings.isEmpty) continue;

      if (positionScores.isEmpty) {
        results[guideList.guideId] = _alphabeticalGroupSort(guideList.bookings);
      } else {
        results[guideList.guideId] = _sortByScores(guideList.bookings, positionScores);
      }

      print('📍 Auto-sorted ${results[guideList.guideId]!.length} bookings for guide ${guideList.guideName}');
    }

    return results;
  }

  /// Build position scores from historical route snapshots.
  ///
  /// For each pickup place, we average its position across all snapshots
  /// where it appears. More recent snapshots get higher weight.
  static Map<String, double> _buildPositionScores(List<List<String>> routeHistory) {
    // Accumulate (weighted sum, weight count) per place
    final sumMap = <String, double>{};
    final weightMap = <String, double>{};

    for (int i = 0; i < routeHistory.length; i++) {
      final route = routeHistory[i];
      // More recent routes (lower i) get higher weight
      // Exponential decay: weight = 0.95^i
      final weight = _decayWeight(i);

      for (int pos = 0; pos < route.length; pos++) {
        final place = _normalizePlace(route[pos]);
        // Normalize position to 0..1 range so routes of different lengths
        // are comparable
        final normalizedPos = route.length > 1
            ? pos / (route.length - 1)
            : 0.0;

        sumMap[place] = (sumMap[place] ?? 0.0) + normalizedPos * weight;
        weightMap[place] = (weightMap[place] ?? 0.0) + weight;
      }
    }

    // Compute weighted averages
    final scores = <String, double>{};
    for (final place in sumMap.keys) {
      scores[place] = sumMap[place]! / weightMap[place]!;
    }

    return scores;
  }

  /// Sort bookings by their pickup place's learned position score.
  /// Same-place bookings are grouped together.
  static List<PickupBooking> _sortByScores(
    List<PickupBooking> bookings,
    Map<String, double> positionScores,
  ) {
    // Default score for unknown places: 1.0 (end of list)
    const unknownScore = 1.0;

    final sorted = List<PickupBooking>.from(bookings);
    sorted.sort((a, b) {
      final placeA = _normalizePlace(a.pickupPlaceName);
      final placeB = _normalizePlace(b.pickupPlaceName);

      final scoreA = positionScores[placeA] ?? unknownScore;
      final scoreB = positionScores[placeB] ?? unknownScore;

      // Primary: sort by learned position
      final scoreCompare = scoreA.compareTo(scoreB);
      if (scoreCompare != 0) return scoreCompare;

      // Secondary: group same pickup place together (alphabetical tiebreaker)
      final placeCompare = a.pickupPlaceName.compareTo(b.pickupPlaceName);
      if (placeCompare != 0) return placeCompare;

      // Tertiary: by customer name within the same place
      return a.customerFullName.compareTo(b.customerFullName);
    });

    return sorted;
  }

  /// Fallback: sort alphabetically by pickup place, grouping same-place
  /// bookings together, with customer name as secondary sort.
  static List<PickupBooking> _alphabeticalGroupSort(List<PickupBooking> bookings) {
    final sorted = List<PickupBooking>.from(bookings);
    sorted.sort((a, b) {
      final placeCompare = a.pickupPlaceName.compareTo(b.pickupPlaceName);
      if (placeCompare != 0) return placeCompare;
      return a.customerFullName.compareTo(b.customerFullName);
    });
    return sorted;
  }

  /// Normalize a pickup place name for consistent matching.
  /// Trims whitespace, lowercases, removes common suffixes.
  static String _normalizePlace(String place) {
    return place.trim().toLowerCase();
  }

  /// Exponential decay weight: more recent = higher weight.
  /// w(i) = 0.95^i  (i=0 is the most recent snapshot)
  static double _decayWeight(int index) {
    // Use pow approximation for performance
    double w = 1.0;
    for (int j = 0; j < index && j < 100; j++) {
      w *= 0.95;
    }
    return w;
  }
}
