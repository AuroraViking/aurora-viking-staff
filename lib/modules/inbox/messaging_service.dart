// Messaging service for the Unified Inbox
// Uses direct Firestore operations (Cloud Functions auth issues on some devices)

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/models/messaging/messaging_models.dart';

class MessagingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ============================================
  // CONVERSATIONS
  // ============================================

  /// Get stream of conversations (real-time updates)
  Stream<List<Conversation>> getConversationsStream({
    ConversationStatus? status,
    String? customerId,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('conversations')
        .orderBy('lastMessageAt', descending: true)
        .limit(limit);

    if (status != null) {
      query = query.where('status', isEqualTo: status.name);
    }

    if (customerId != null) {
      query = query.where('customerId', isEqualTo: customerId);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Conversation.fromFirestore(doc)).toList();
    });
  }

  /// Get active conversations stream (excludes archived only)
  Stream<List<Conversation>> getActiveConversationsStream({int limit = 50}) {
    // Get all conversations except archived
    // The UI will filter by isHandled for Main vs sub-inboxes
    return _firestore
        .collection('conversations')
        .where('status', whereIn: ['active', 'resolved'])  // Include resolved!
        .orderBy('lastMessageAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Conversation.fromFirestore(doc)).toList();
    });
  }
  
  /// Get ALL conversations (including resolved, for sub-inbox views)
  Stream<List<Conversation>> getAllConversationsStream({int limit = 100}) {
    return _firestore
        .collection('conversations')
        .orderBy('lastMessageAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Conversation.fromFirestore(doc)).toList();
    });
  }

  /// Get single conversation
  Future<Conversation?> getConversation(String conversationId) async {
    final doc = await _firestore.collection('conversations').doc(conversationId).get();
    if (!doc.exists) return null;
    return Conversation.fromFirestore(doc);
  }

  /// Get single conversation stream
  Stream<Conversation?> getConversationStream(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return Conversation.fromFirestore(doc);
    });
  }

  /// Mark conversation as read (direct Firestore)
  Future<void> markConversationAsRead(String conversationId) async {
    try {
      await _firestore.collection('conversations').doc(conversationId).update({
        'unreadCount': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error marking conversation as read: $e');
    }
  }

  /// Update conversation status (direct Firestore)
  /// When marking as resolved, also set isHandled so it moves out of Main inbox
  Future<void> updateConversationStatus(String conversationId, ConversationStatus status) async {
    try {
      final updates = <String, dynamic>{
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      // If resolving, also mark as handled (same as "complete")
      if (status == ConversationStatus.resolved) {
        updates['isHandled'] = true;
        updates['handledAt'] = FieldValue.serverTimestamp();
      }
      
      await _firestore.collection('conversations').doc(conversationId).update(updates);
    } catch (e) {
      print('Error updating conversation status: $e');
    }
  }

  /// Assign conversation to a user
  Future<void> assignConversation(String conversationId, String userId, String userName) async {
    try {
      await _firestore.collection('conversations').doc(conversationId).update({
        'assignedTo': userId,
        'assignedToName': userName,
        'assignedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error assigning conversation: $e');
      rethrow;
    }
  }

  /// Unassign conversation
  Future<void> unassignConversation(String conversationId) async {
    try {
      await _firestore.collection('conversations').doc(conversationId).update({
        'assignedTo': null,
        'assignedToName': null,
        'assignedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error unassigning conversation: $e');
      rethrow;
    }
  }

  /// Mark conversation as complete (handled) - removes from Main inbox
  Future<void> markConversationComplete(String conversationId, String userId) async {
    try {
      await _firestore.collection('conversations').doc(conversationId).update({
        'isHandled': true,
        'handledAt': FieldValue.serverTimestamp(),
        'handledBy': userId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error marking conversation complete: $e');
      rethrow;
    }
  }

  /// Reopen a handled conversation (move back to Main inbox)
  Future<void> reopenConversation(String conversationId) async {
    try {
      await _firestore.collection('conversations').doc(conversationId).update({
        'isHandled': false,
        'handledAt': null,
        'handledBy': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error reopening conversation: $e');
      rethrow;
    }
  }

  // ============================================
  // MESSAGES
  // ============================================

  /// Get stream of messages for a conversation
  Stream<List<Message>> getMessagesStream(String conversationId) {
    print('📨 Loading messages for conversation: $conversationId');
    return _firestore
        .collection('messages')
        .where('conversationId', isEqualTo: conversationId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
      print('📬 Got ${snapshot.docs.length} messages');
      final messages = snapshot.docs.map((doc) {
        final msg = Message.fromFirestore(doc);
        print('   - Message ${msg.id}: content length = ${msg.content.length}');
        return msg;
      }).toList();
      return messages;
    });
  }

  /// Send a message (direct Firestore - bypasses Cloud Functions)
  Future<String?> sendMessage({
    required String conversationId,
    required String content,
    String? channel,
  }) async {
    try {
      print('📤 Sending message to conversation: $conversationId');
      
      // Get conversation to find customer
      final convDoc = await _firestore.collection('conversations').doc(conversationId).get();
      if (!convDoc.exists) {
        throw Exception('Conversation not found');
      }
      final convData = convDoc.data()!;
      final customerId = convData['customerId'] as String;
      final convChannel = channel ?? convData['channel'] as String;
      
      // Get customer for email
      final customerDoc = await _firestore.collection('customers').doc(customerId).get();
      final customerData = customerDoc.data();
      final customerEmail = customerData?['email'] ?? customerData?['channels']?['gmail'] ?? '';
      
      // Extract booking references from content
      final bookingRegex = RegExp(r'\b(AV|AUR|av|aur)-\d+\b', caseSensitive: false);
      final matches = bookingRegex.allMatches(content);
      final detectedBookingNumbers = matches.map((m) => m.group(0)!.toUpperCase()).toList();
      
      // Create outbound message
      final messageDoc = await _firestore.collection('messages').add({
        'conversationId': conversationId,
        'customerId': customerId,
        'channel': convChannel,
        'direction': 'outbound',
        'content': content,
        'timestamp': FieldValue.serverTimestamp(),
        'channelMetadata': {
          if (convChannel == 'gmail') 'gmail': {
            'to': [customerEmail],
            'from': 'info@auroraviking.is',
            'threadId': convData['channelMetadata']?['gmail']?['threadId'] ?? '',
          },
        },
        'bookingIds': [],
        'detectedBookingNumbers': detectedBookingNumbers,
        'status': 'responded',
        'handledAt': FieldValue.serverTimestamp(),
        'flaggedForReview': false,
        'priority': 'normal',
      });
      
      print('📨 Outbound message created: ${messageDoc.id}');
      
      // Update conversation
      await convDoc.reference.update({
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessagePreview': content.length > 100 ? '${content.substring(0, 100)}...' : content,
        'unreadCount': 0,
        'messageIds': FieldValue.arrayUnion([messageDoc.id]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ Message sent successfully!');
      
      // Note: In production, you'd also need to actually send the email via Gmail API
      // For now, this just stores the message in Firestore
      
      return messageDoc.id;
    } catch (e) {
      print('❌ Error sending message: $e');
      rethrow;
    }
  }

  // ============================================
  // CUSTOMERS
  // ============================================

  /// Get customer by ID
  Future<Customer?> getCustomer(String customerId) async {
    final doc = await _firestore.collection('customers').doc(customerId).get();
    if (!doc.exists) return null;
    return Customer.fromFirestore(doc);
  }

  /// Get customer stream
  Stream<Customer?> getCustomerStream(String customerId) {
    return _firestore
        .collection('customers')
        .doc(customerId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return Customer.fromFirestore(doc);
    });
  }

  // ============================================
  // STATISTICS
  // ============================================

  /// Get total unread count across all active conversations
  Stream<int> getUnreadCountStream() {
    return _firestore
        .collection('conversations')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.fold<int>(0, (sum, doc) {
        final data = doc.data();
        return sum + ((data['unreadCount'] as int?) ?? 0);
      });
    });
  }

  /// Get counts by status
  Future<Map<ConversationStatus, int>> getStatusCounts() async {
    final counts = <ConversationStatus, int>{};
    
    for (final status in ConversationStatus.values) {
      final snapshot = await _firestore
          .collection('conversations')
          .where('status', isEqualTo: status.name)
          .count()
          .get();
      counts[status] = snapshot.count ?? 0;
    }
    
    return counts;
  }

  // ============================================
  // TESTING / DEVELOPMENT
  // ============================================

  /// Create a test message for development (direct Firestore - bypasses Cloud Functions)
  Future<Map<String, dynamic>?> createTestMessage({
    String email = 'test@example.com',
    String content = 'Hi, I have a question about my booking AV-12345.',
    String subject = 'Test inquiry',
  }) async {
    try {
      print('📧 Creating test message directly in Firestore...');
      
      // Extract booking references
      final bookingRegex = RegExp(r'\b(AV|av)-\d+\b', caseSensitive: false);
      final matches = bookingRegex.allMatches('$content $subject');
      final detectedBookingNumbers = matches.map((m) => m.group(0)!.toUpperCase()).toList();
      print('🔍 Detected booking refs: ${detectedBookingNumbers.join(', ')}');
      
      // Find or create customer
      String customerId;
      final customerQuery = await _firestore
          .collection('customers')
          .where('channels.gmail', isEqualTo: email)
          .limit(1)
          .get();
      
      if (customerQuery.docs.isNotEmpty) {
        customerId = customerQuery.docs.first.id;
        // Update last contact
        await _firestore.collection('customers').doc(customerId).update({
          'lastContact': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('👤 Found existing customer: $customerId');
      } else {
        // Create new customer
        final customerName = email.split('@')[0].replaceAll(RegExp(r'[._]'), ' ');
        final customerDoc = await _firestore.collection('customers').add({
          'name': customerName,
          'email': email,
          'channels': {'gmail': email},
          'totalBookings': 0,
          'upcomingBookings': [],
          'pastBookings': [],
          'language': 'en',
          'vipStatus': false,
          'pastInteractions': 0,
          'averageResponseTime': 0,
          'commonRequests': [],
          'firstContact': FieldValue.serverTimestamp(),
          'lastContact': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        customerId = customerDoc.id;
        print('👤 Created new customer: $customerId');
      }
      
      // Create conversation
      final threadId = 'thread-${DateTime.now().millisecondsSinceEpoch}';
      final conversationDoc = await _firestore.collection('conversations').add({
        'customerId': customerId,
        'channel': 'gmail',
        'subject': subject,
        'bookingIds': detectedBookingNumbers,
        'messageIds': [],
        'status': 'active',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessagePreview': content.length > 100 ? '${content.substring(0, 100)}...' : content,
        'unreadCount': 1,
        'channelMetadata': {'gmail': {'threadId': threadId}},
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final conversationId = conversationDoc.id;
      print('💬 Created conversation: $conversationId');
      
      // Create message
      final messageDoc = await _firestore.collection('messages').add({
        'conversationId': conversationId,
        'customerId': customerId,
        'channel': 'gmail',
        'direction': 'inbound',
        'subject': subject,
        'content': content,
        'timestamp': FieldValue.serverTimestamp(),
        'channelMetadata': {
          'gmail': {
            'threadId': threadId,
            'messageId': 'test-${DateTime.now().millisecondsSinceEpoch}',
            'from': email,
            'to': ['info@auroraviking.is'],
          },
        },
        'bookingIds': [],
        'detectedBookingNumbers': detectedBookingNumbers,
        'status': 'pending',
        'flaggedForReview': false,
        'priority': 'normal',
      });
      final messageId = messageDoc.id;
      print('📨 Created message: $messageId');
      
      // Update conversation with message ID
      await conversationDoc.update({
        'messageIds': FieldValue.arrayUnion([messageId]),
      });
      
      print('✅ Test message created successfully!');
      
      return {
        'success': true,
        'messageId': messageId,
        'conversationId': conversationId,
        'customerId': customerId,
        'detectedBookingNumbers': detectedBookingNumbers,
      };
    } catch (e) {
      print('❌ Error creating test message: $e');
      rethrow;
    }
  }

  // ============================================
  // AI LEARNING DATA
  // ============================================

  /// Log AI draft action (used, dismissed) for learning
  Future<void> logAiDraftAction({
    required String messageId,
    required String action,
    required String draftContent,
    required double confidence,
  }) async {
    try {
      await _firestore.collection('ai_learning').add({
        'type': 'draft_action',
        'messageId': messageId,
        'action': action, // 'used', 'dismissed'
        'draftContent': draftContent,
        'confidence': confidence,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Error logging AI draft action: $e');
      rethrow;
    }
  }

  /// Log AI draft edit (original vs edited content) for learning
  Future<void> logAiDraftEdit({
    required String messageId,
    required String originalDraft,
    required String editedContent,
  }) async {
    try {
      // Calculate edit distance / similarity
      final originalLength = originalDraft.length;
      final editedLength = editedContent.length;
      final lengthDiff = (originalLength - editedLength).abs();
      final similarity = originalDraft == editedContent 
          ? 1.0 
          : 1.0 - (lengthDiff / (originalLength > 0 ? originalLength : 1)).clamp(0.0, 1.0);

      await _firestore.collection('ai_learning').add({
        'type': 'draft_edit',
        'messageId': messageId,
        'originalDraft': originalDraft,
        'editedContent': editedContent,
        'editSimilarity': similarity,
        'originalLength': originalLength,
        'editedLength': editedLength,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Error logging AI draft edit: $e');
      rethrow;
    }
  }

  /// Get AI learning stats
  Future<Map<String, dynamic>> getAiLearningStats() async {
    try {
      final actionsSnapshot = await _firestore
          .collection('ai_learning')
          .where('type', isEqualTo: 'draft_action')
          .get();

      int usedCount = 0;
      int dismissedCount = 0;
      double totalConfidenceUsed = 0;

      for (final doc in actionsSnapshot.docs) {
        final data = doc.data();
        if (data['action'] == 'used') {
          usedCount++;
          totalConfidenceUsed += (data['confidence'] ?? 0.0);
        } else if (data['action'] == 'dismissed') {
          dismissedCount++;
        }
      }

      final editsSnapshot = await _firestore
          .collection('ai_learning')
          .where('type', isEqualTo: 'draft_edit')
          .get();

      double totalSimilarity = 0;
      for (final doc in editsSnapshot.docs) {
        totalSimilarity += (doc.data()['editSimilarity'] ?? 0.0);
      }

      final total = usedCount + dismissedCount;
      return {
        'totalDrafts': total,
        'usedCount': usedCount,
        'dismissedCount': dismissedCount,
        'acceptanceRate': total > 0 ? usedCount / total : 0.0,
        'averageConfidenceUsed': usedCount > 0 ? totalConfidenceUsed / usedCount : 0.0,
        'editsCount': editsSnapshot.docs.length,
        'averageSimilarity': editsSnapshot.docs.isNotEmpty 
            ? totalSimilarity / editsSnapshot.docs.length 
            : 0.0,
      };
    } catch (e) {
      print('❌ Error getting AI learning stats: $e');
      return {};
    }
  }
}

