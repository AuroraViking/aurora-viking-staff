import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pickup_overgroup_model.dart';

/// Service to manage pickup place overgroups in Firestore.
///
/// Overgroups let admins unify multiple pickup place names (that represent
/// the same physical location but are named differently by resellers) under
/// a single canonical display name.
class PickupOvergroupService {
  static final PickupOvergroupService _instance = PickupOvergroupService._internal();
  factory PickupOvergroupService() => _instance;
  PickupOvergroupService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collectionName = 'pickup_overgroups';

  // ─── In-memory cache ────────────────────────────────────────────────
  List<PickupOvergroup>? _cachedOvergroups;
  Map<String, String>? _cachedPlaceToGroupMap;

  void _invalidateCache() {
    _cachedOvergroups = null;
    _cachedPlaceToGroupMap = null;
  }

  // ─── Read ──────────────────────────────────────────────────────────

  /// Realtime stream of all overgroups.
  Stream<List<PickupOvergroup>> getOvergroups() {
    return _firestore
        .collection(_collectionName)
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
      final groups = snapshot.docs
          .map((doc) => PickupOvergroup.fromMap(doc.id, doc.data()))
          .toList();
      _cachedOvergroups = groups;
      _cachedPlaceToGroupMap = null; // invalidate derived cache
      return groups;
    });
  }

  /// One-shot fetch of all overgroups.
  Future<List<PickupOvergroup>> getOvergroupsOnce() async {
    if (_cachedOvergroups != null) return _cachedOvergroups!;
    final snapshot = await _firestore
        .collection(_collectionName)
        .orderBy('name')
        .get();
    final groups = snapshot.docs
        .map((doc) => PickupOvergroup.fromMap(doc.id, doc.data()))
        .toList();
    _cachedOvergroups = groups;
    return groups;
  }

  // ─── Write ─────────────────────────────────────────────────────────

  Future<bool> createOvergroup(String name, List<String> members) async {
    try {
      await _firestore.collection(_collectionName).add({
        'name': name,
        'members': members,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _invalidateCache();
      print('✅ Created overgroup: $name with ${members.length} members');
      return true;
    } catch (e) {
      print('❌ Error creating overgroup: $e');
      return false;
    }
  }

  Future<bool> updateOvergroup(String id, {String? name, List<String>? members}) async {
    try {
      final data = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
      if (name != null) data['name'] = name;
      if (members != null) data['members'] = members;
      await _firestore.collection(_collectionName).doc(id).update(data);
      _invalidateCache();
      print('✅ Updated overgroup $id');
      return true;
    } catch (e) {
      print('❌ Error updating overgroup: $e');
      return false;
    }
  }

  Future<bool> deleteOvergroup(String id) async {
    try {
      await _firestore.collection(_collectionName).doc(id).delete();
      _invalidateCache();
      print('✅ Deleted overgroup $id');
      return true;
    } catch (e) {
      print('❌ Error deleting overgroup: $e');
      return false;
    }
  }

  Future<bool> addMemberToOvergroup(String overgroupId, String memberName) async {
    try {
      await _firestore.collection(_collectionName).doc(overgroupId).update({
        'members': FieldValue.arrayUnion([memberName]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _invalidateCache();
      print('✅ Added "$memberName" to overgroup $overgroupId');
      return true;
    } catch (e) {
      print('❌ Error adding member to overgroup: $e');
      return false;
    }
  }

  Future<bool> removeMemberFromOvergroup(String overgroupId, String memberName) async {
    try {
      await _firestore.collection(_collectionName).doc(overgroupId).update({
        'members': FieldValue.arrayRemove([memberName]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _invalidateCache();
      print('✅ Removed "$memberName" from overgroup $overgroupId');
      return true;
    } catch (e) {
      print('❌ Error removing member from overgroup: $e');
      return false;
    }
  }

  // ─── Lookup helpers ────────────────────────────────────────────────

  /// Build a map from any member pickup name → overgroup canonical name.
  /// Uses a normalised (trimmed, lowercase) key for fuzzy-ish matching.
  Future<Map<String, String>> buildPlaceToGroupMap() async {
    if (_cachedPlaceToGroupMap != null) return _cachedPlaceToGroupMap!;

    final overgroups = await getOvergroupsOnce();
    final map = <String, String>{};
    for (final group in overgroups) {
      for (final member in group.members) {
        map[member.trim().toLowerCase()] = group.name;
      }
    }
    _cachedPlaceToGroupMap = map;
    return map;
  }

  /// Look up the canonical group name for a given pickup place.
  /// Returns null if the place is not in any overgroup.
  Future<String?> getOvergroupNameForPlace(String placeName) async {
    final map = await buildPlaceToGroupMap();
    return map[placeName.trim().toLowerCase()];
  }
}
