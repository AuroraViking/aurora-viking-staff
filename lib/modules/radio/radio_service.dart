/// Firestore CRUD service for radio channels and messages (voice, text, image).
import 'package:cloud_firestore/cloud_firestore.dart';

/// Message types supported by the radio system.
enum RadioMessageType { voice, text, image }

class RadioMessage {
  final String id;
  final String channelId;
  final String senderId;
  final String senderName;
  final RadioMessageType type;
  final String audioBase64;   // voice only
  final int durationMs;       // voice only
  final String textContent;   // text only
  final String imageUrl;      // image only
  final DateTime createdAt;

  RadioMessage({
    required this.id,
    required this.channelId,
    required this.senderId,
    required this.senderName,
    this.type = RadioMessageType.voice,
    this.audioBase64 = '',
    this.durationMs = 0,
    this.textContent = '',
    this.imageUrl = '',
    required this.createdAt,
  });

  factory RadioMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RadioMessage(
      id: doc.id,
      channelId: data['channelId'] ?? '',
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Unknown',
      type: RadioMessageType.values.firstWhere(
        (e) => e.name == (data['type'] ?? 'voice'),
        orElse: () => RadioMessageType.voice,
      ),
      audioBase64: data['audioBase64'] ?? '',
      durationMs: data['durationMs'] ?? 0,
      textContent: data['textContent'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'channelId': channelId,
        'senderId': senderId,
        'senderName': senderName,
        'type': type.name,
        'audioBase64': audioBase64,
        'durationMs': durationMs,
        'textContent': textContent,
        'imageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

class RadioChannel {
  final String id;
  final String name;
  final String type; // 'fleet', 'dispatch', 'direct'
  final List<String> members; // user IDs (for direct channels)
  final DateTime createdAt;

  RadioChannel({
    required this.id,
    required this.name,
    required this.type,
    required this.members,
    required this.createdAt,
  });

  factory RadioChannel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RadioChannel(
      id: doc.id,
      name: data['name'] ?? '',
      type: data['type'] ?? 'fleet',
      members: List<String>.from(data['members'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class RadioService {
  static final _firestore = FirebaseFirestore.instance;
  static final _channelsRef = _firestore.collection('radio_channels');
  static final _messagesRef = _firestore.collection('radio_messages');

  // ──────────── Channels ────────────

  /// Ensure default channels (fleet) exist.
  static Future<void> ensureDefaultChannels() async {
    final fleetDoc = await _channelsRef.doc('fleet').get();
    if (!fleetDoc.exists) {
      await _channelsRef.doc('fleet').set({
        'name': 'Fleet',
        'type': 'fleet',
        'members': [],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Delete a channel and all its messages.
  static Future<void> deleteChannel(String channelId) async {
    // Delete all messages in the channel.
    final msgs = await _messagesRef
        .where('channelId', isEqualTo: channelId)
        .get();
    final batch = _firestore.batch();
    for (final doc in msgs.docs) {
      batch.delete(doc.reference);
    }
    // Delete the channel itself.
    batch.delete(_channelsRef.doc(channelId));
    await batch.commit();
  }

  /// Get channels accessible to the given user.
  static Future<List<RadioChannel>> getChannels(String userId) async {
    final snapshot = await _channelsRef.get();
    final channels = snapshot.docs.map((d) => RadioChannel.fromFirestore(d)).toList();

    // Filter: fleet visible to everyone,
    // direct channels only to their members.
    return channels.where((ch) {
      if (ch.type == 'fleet') return true;
      if (ch.type == 'dispatch') return false; // hide legacy dispatch channels
      return ch.members.contains(userId);
    }).toList();
  }

  /// Create a direct channel between two users. Returns the channel ID.
  static Future<String> createDirectChannel({
    required String fromUserId,
    required String fromUserName,
    required String toUserId,
    required String toUserName,
  }) async {
    // Deterministic ID so we don't create duplicates.
    final ids = [fromUserId, toUserId]..sort();
    final channelId = 'dm_${ids[0]}_${ids[1]}';

    final doc = await _channelsRef.doc(channelId).get();
    if (!doc.exists) {
      await _channelsRef.doc(channelId).set({
        'name': '$fromUserName ↔ $toUserName',
        'type': 'direct',
        'members': ids,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return channelId;
  }

  // ──────────── Messages ────────────

  /// Real-time stream of messages in a channel, ordered by time ascending.
  /// Sorting is done client-side to avoid needing a composite Firestore index.
  static Stream<List<RadioMessage>> streamMessages(String channelId) {
    return _messagesRef
        .where('channelId', isEqualTo: channelId)
        .limit(100)
        .snapshots()
        .map((snap) {
          final msgs = snap.docs
              .map((d) => RadioMessage.fromFirestore(d))
              .toList();
          msgs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return msgs;
        });
  }

  /// Send a voice note to a channel.
  static Future<void> sendVoiceNote({
    required String channelId,
    required String senderId,
    required String senderName,
    required String audioBase64,
    required int durationMs,
  }) async {
    await _messagesRef.add(RadioMessage(
      id: '',
      channelId: channelId,
      senderId: senderId,
      senderName: senderName,
      type: RadioMessageType.voice,
      audioBase64: audioBase64,
      durationMs: durationMs,
      createdAt: DateTime.now(),
    ).toFirestore());
  }

  /// Send a text message to a channel.
  static Future<void> sendTextMessage({
    required String channelId,
    required String senderId,
    required String senderName,
    required String textContent,
  }) async {
    await _messagesRef.add(RadioMessage(
      id: '',
      channelId: channelId,
      senderId: senderId,
      senderName: senderName,
      type: RadioMessageType.text,
      textContent: textContent,
      createdAt: DateTime.now(),
    ).toFirestore());
  }

  /// Send an image message to a channel.
  static Future<void> sendImageMessage({
    required String channelId,
    required String senderId,
    required String senderName,
    required String imageUrl,
  }) async {
    await _messagesRef.add(RadioMessage(
      id: '',
      channelId: channelId,
      senderId: senderId,
      senderName: senderName,
      type: RadioMessageType.image,
      imageUrl: imageUrl,
      createdAt: DateTime.now(),
    ).toFirestore());
  }

  /// Get list of all staff users (for creating direct channels).
  static Future<List<Map<String, String>>> getStaffUsers() async {
    final snapshot = await _firestore.collection('users').get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': (data['fullName'] ?? data['email'] ?? 'Unknown') as String,
        'role': (data['role'] ?? 'staff') as String,
      };
    }).toList();
  }
}
