import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BusManagementService {
  static final BusManagementService _instance = BusManagementService._internal();
  factory BusManagementService() => _instance;
  BusManagementService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Bus data structure
  static const String _collectionName = 'buses';

  // Get all buses
  Stream<List<Map<String, dynamic>>> getAllBuses() {
    return _firestore
        .collection(_collectionName)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {
                  'id': doc.id,
                  ...doc.data(),
                })
            .toList());
  }

  // Get a specific bus
  Future<Map<String, dynamic>?> getBus(String busId) async {
    try {
      final doc = await _firestore.collection(_collectionName).doc(busId).get();
      if (doc.exists) {
        return {
          'id': doc.id,
          ...doc.data()!,
        };
      }
      return null;
    } catch (e) {
      print('❌ Error getting bus: $e');
      return null;
    }
  }

  // Add a new bus
  Future<bool> addBus({
    required String name,
    required String licensePlate,
    required String color,
    String? description,
    bool isActive = true,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ User not authenticated');
        return false;
      }

      final busData = {
        'name': name,
        'licensePlate': licensePlate,
        'color': color,
        'description': description ?? '',
        'isActive': isActive,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _firestore.collection(_collectionName).add(busData);
      print('✅ Bus added successfully: $name');
      return true;
    } catch (e) {
      print('❌ Error adding bus: $e');
      return false;
    }
  }

  // Update a bus
  Future<bool> updateBus({
    required String busId,
    String? name,
    String? licensePlate,
    String? color,
    String? description,
    bool? isActive,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ User not authenticated');
        return false;
      }

      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      };

      if (name != null) updateData['name'] = name;
      if (licensePlate != null) updateData['licensePlate'] = licensePlate;
      if (color != null) updateData['color'] = color;
      if (description != null) updateData['description'] = description;
      if (isActive != null) updateData['isActive'] = isActive;

      await _firestore.collection(_collectionName).doc(busId).update(updateData);
      print('✅ Bus updated successfully: $busId');
      return true;
    } catch (e) {
      print('❌ Error updating bus: $e');
      return false;
    }
  }

  // Delete a bus
  Future<bool> deleteBus(String busId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ User not authenticated');
        return false;
      }

      // Check if bus is currently being tracked
      final trackingDoc = await _firestore.collection('bus_locations').doc(busId).get();
      if (trackingDoc.exists) {
        print('⚠️ Cannot delete bus that is currently being tracked');
        return false;
      }

      // Delete the bus
      await _firestore.collection(_collectionName).doc(busId).delete();
      
      // Clean up related data
      await _cleanupBusData(busId);
      
      print('✅ Bus deleted successfully: $busId');
      return true;
    } catch (e) {
      print('❌ Error deleting bus: $e');
      return false;
    }
  }

  // Clean up bus-related data when deleting
  Future<void> _cleanupBusData(String busId) async {
    try {
      // Delete location history for this bus
      final historyQuery = await _firestore
          .collection('location_history')
          .where('busId', isEqualTo: busId)
          .get();

      if (historyQuery.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in historyQuery.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        print('🧹 Cleaned up ${historyQuery.docs.length} location history entries for bus $busId');
      }

      // Delete any reordered bookings for this bus
      final reorderedQuery = await _firestore
          .collection('reordered_bookings')
          .where('busId', isEqualTo: busId)
          .get();

      if (reorderedQuery.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in reorderedQuery.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        print('🧹 Cleaned up ${reorderedQuery.docs.length} reordered booking entries for bus $busId');
      }
    } catch (e) {
      print('❌ Error cleaning up bus data: $e');
    }
  }

  // Get active buses only
  Stream<List<Map<String, dynamic>>> getActiveBuses() {
    return _firestore
        .collection(_collectionName)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final buses = snapshot.docs
              .map((doc) => {
                    'id': doc.id,
                    ...doc.data(),
                  })
              .toList();
          // Sort in memory instead of using orderBy
          buses.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
          return buses;
        });
  }

  // Toggle bus active status
  Future<bool> toggleBusStatus(String busId, bool isActive) async {
    return await updateBus(busId: busId, isActive: isActive);
  }

  // Check if bus exists
  Future<bool> busExists(String busId) async {
    try {
      final doc = await _firestore.collection(_collectionName).doc(busId).get();
      return doc.exists;
    } catch (e) {
      print('❌ Error checking if bus exists: $e');
      return false;
    }
  }

  // Get bus by license plate
  Future<Map<String, dynamic>?> getBusByLicensePlate(String licensePlate) async {
    try {
      final query = await _firestore
          .collection(_collectionName)
          .where('licensePlate', isEqualTo: licensePlate)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        return {
          'id': doc.id,
          ...doc.data(),
        };
      }
      return null;
    } catch (e) {
      print('❌ Error getting bus by license plate: $e');
      return null;
    }
  }
} 