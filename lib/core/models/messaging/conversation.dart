// Conversation model for the Unified Inbox system
// Groups related messages into threads

import 'package:cloud_firestore/cloud_firestore.dart';

enum ConversationStatus { active, resolved, archived }

class Conversation {
  final String id;
  final String customerId;
  final String? customerName;  // Customer/visitor name
  final String? customerEmail; // Customer/visitor email
  final String channel;
  final String? inboxEmail;  // Which inbox this belongs to (info@, photo@, etc.)
  final String? subject;
  final List<String> bookingIds;
  final List<String> messageIds;
  final ConversationStatus status;
  final DateTime lastMessageAt;
  final String lastMessagePreview;
  final int unreadCount;
  final String? assignedTo;
  final String? assignedToName;  // Display name of assigned admin
  final DateTime? assignedAt;
  final bool isHandled;  // True when marked complete
  final DateTime? handledAt;
  final String? handledBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation({
    required this.id,
    required this.customerId,
    this.customerName,
    this.customerEmail,
    required this.channel,
    this.inboxEmail,
    this.subject,
    this.bookingIds = const [],
    this.messageIds = const [],
    this.status = ConversationStatus.active,
    required this.lastMessageAt,
    required this.lastMessagePreview,
    this.unreadCount = 0,
    this.assignedTo,
    this.assignedToName,
    this.assignedAt,
    this.isHandled = false,
    this.handledAt,
    this.handledBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    // Extract inbox from channelMetadata if available
    String? inboxEmail = json['inboxEmail'];
    if (inboxEmail == null && json['channelMetadata'] != null) {
      inboxEmail = json['channelMetadata']?['gmail']?['inbox'];
    }
    
    return Conversation(
      id: json['id'] ?? '',
      customerId: json['customerId'] ?? '',
      customerName: json['customerName'],
      customerEmail: json['customerEmail'],
      channel: json['channel'] ?? 'gmail',
      inboxEmail: inboxEmail,
      subject: json['subject'],
      bookingIds: List<String>.from(json['bookingIds'] ?? []),
      messageIds: List<String>.from(json['messageIds'] ?? []),
      status: ConversationStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ConversationStatus.active,
      ),
      lastMessageAt: _parseDateTime(json['lastMessageAt']) ?? DateTime.now(),
      lastMessagePreview: json['lastMessagePreview'] ?? '',
      unreadCount: json['unreadCount'] ?? 0,
      assignedTo: json['assignedTo'],
      assignedToName: json['assignedToName'],
      assignedAt: _parseDateTime(json['assignedAt']),
      isHandled: json['isHandled'] ?? false,
      handledAt: _parseDateTime(json['handledAt']),
      handledBy: json['handledBy'],
      createdAt: _parseDateTime(json['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDateTime(json['updatedAt']) ?? DateTime.now(),
    );
  }

  factory Conversation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Conversation.fromJson({
      ...data,
      'id': doc.id,
    });
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customerId': customerId,
      'customerName': customerName,
      'customerEmail': customerEmail,
      'channel': channel,
      'inboxEmail': inboxEmail,
      'subject': subject,
      'bookingIds': bookingIds,
      'messageIds': messageIds,
      'status': status.name,
      'lastMessageAt': Timestamp.fromDate(lastMessageAt),
      'lastMessagePreview': lastMessagePreview,
      'unreadCount': unreadCount,
      'assignedTo': assignedTo,
      'assignedToName': assignedToName,
      'assignedAt': assignedAt != null ? Timestamp.fromDate(assignedAt!) : null,
      'isHandled': isHandled,
      'handledAt': handledAt != null ? Timestamp.fromDate(handledAt!) : null,
      'handledBy': handledBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Conversation copyWith({
    String? id,
    String? customerId,
    String? channel,
    String? inboxEmail,
    String? subject,
    List<String>? bookingIds,
    List<String>? messageIds,
    ConversationStatus? status,
    DateTime? lastMessageAt,
    String? lastMessagePreview,
    int? unreadCount,
    String? assignedTo,
    String? assignedToName,
    DateTime? assignedAt,
    bool? isHandled,
    DateTime? handledAt,
    String? handledBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      channel: channel ?? this.channel,
      inboxEmail: inboxEmail ?? this.inboxEmail,
      subject: subject ?? this.subject,
      bookingIds: bookingIds ?? this.bookingIds,
      messageIds: messageIds ?? this.messageIds,
      status: status ?? this.status,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      unreadCount: unreadCount ?? this.unreadCount,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedToName: assignedToName ?? this.assignedToName,
      assignedAt: assignedAt ?? this.assignedAt,
      isHandled: isHandled ?? this.isHandled,
      handledAt: handledAt ?? this.handledAt,
      handledBy: handledBy ?? this.handledBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Check if conversation has unread messages
  bool get hasUnread => unreadCount > 0;
  
  /// Check if conversation is assigned to someone
  bool get isAssigned => assignedTo != null;

  /// Check if conversation is active
  bool get isActive => status == ConversationStatus.active;

  /// Check if conversation is resolved
  bool get isResolved => status == ConversationStatus.resolved;

  /// Check if conversation is archived
  bool get isArchived => status == ConversationStatus.archived;

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

