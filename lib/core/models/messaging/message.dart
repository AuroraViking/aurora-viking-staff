// Message model for the Unified Inbox system
// Represents a single message from any channel (Gmail, Wix, WhatsApp)

import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageChannel { gmail, wix, whatsapp }
enum MessageDirection { inbound, outbound }
enum MessageStatus { pending, draftReady, responded, autoHandled, archived }
enum MessagePriority { low, normal, high, urgent }

class Message {
  final String id;
  final String conversationId;
  final String customerId;
  final MessageChannel channel;
  final MessageDirection direction;
  final String content;
  final String? contentHtml;  // Rich HTML content for display
  final DateTime timestamp;
  final String? subject;
  final ChannelMetadata channelMetadata;
  final List<String> bookingIds;
  final List<String> detectedBookingNumbers;
  final AiDraft? aiDraft;
  final List<SuggestedAction> suggestedActions;
  final MessageStatus status;
  final String? handledBy;
  final DateTime? handledAt;
  final bool flaggedForReview;
  final String? flagReason;
  final MessagePriority priority;
  final String? sentiment;
  final String? intent;

  Message({
    required this.id,
    required this.conversationId,
    required this.customerId,
    required this.channel,
    required this.direction,
    required this.content,
    this.contentHtml,
    required this.timestamp,
    this.subject,
    required this.channelMetadata,
    this.bookingIds = const [],
    this.detectedBookingNumbers = const [],
    this.aiDraft,
    this.suggestedActions = const [],
    this.status = MessageStatus.pending,
    this.handledBy,
    this.handledAt,
    this.flaggedForReview = false,
    this.flagReason,
    this.priority = MessagePriority.normal,
    this.sentiment,
    this.intent,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? '',
      conversationId: json['conversationId'] ?? '',
      customerId: json['customerId'] ?? '',
      channel: MessageChannel.values.firstWhere(
        (e) => e.name == json['channel'],
        orElse: () => MessageChannel.gmail,
      ),
      direction: MessageDirection.values.firstWhere(
        (e) => e.name == json['direction'],
        orElse: () => MessageDirection.inbound,
      ),
      content: json['content'] ?? '',
      contentHtml: json['contentHtml'],
      timestamp: _parseDateTime(json['timestamp']) ?? DateTime.now(),
      subject: json['subject'],
      channelMetadata: ChannelMetadata.fromJson(json['channelMetadata'] ?? {}),
      bookingIds: List<String>.from(json['bookingIds'] ?? []),
      detectedBookingNumbers: List<String>.from(json['detectedBookingNumbers'] ?? []),
      aiDraft: json['aiDraft'] != null ? AiDraft.fromJson(json['aiDraft']) : null,
      suggestedActions: (json['suggestedActions'] as List<dynamic>?)
          ?.map((e) => SuggestedAction.fromJson(e))
          .toList() ?? [],
      status: MessageStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MessageStatus.pending,
      ),
      handledBy: json['handledBy'],
      handledAt: _parseDateTime(json['handledAt']),
      flaggedForReview: json['flaggedForReview'] ?? false,
      flagReason: json['flagReason'],
      priority: MessagePriority.values.firstWhere(
        (e) => e.name == json['priority'],
        orElse: () => MessagePriority.normal,
      ),
      sentiment: json['sentiment'],
      intent: json['intent'],
    );
  }

  factory Message.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Message.fromJson({
      ...data,
      'id': doc.id,
    });
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'customerId': customerId,
      'channel': channel.name,
      'direction': direction.name,
      'content': content,
      'contentHtml': contentHtml,
      'timestamp': Timestamp.fromDate(timestamp),
      'subject': subject,
      'channelMetadata': channelMetadata.toJson(),
      'bookingIds': bookingIds,
      'detectedBookingNumbers': detectedBookingNumbers,
      'aiDraft': aiDraft?.toJson(),
      'suggestedActions': suggestedActions.map((e) => e.toJson()).toList(),
      'status': status.name,
      'handledBy': handledBy,
      'handledAt': handledAt != null ? Timestamp.fromDate(handledAt!) : null,
      'flaggedForReview': flaggedForReview,
      'flagReason': flagReason,
      'priority': priority.name,
      'sentiment': sentiment,
      'intent': intent,
    };
  }

  Message copyWith({
    String? id,
    String? conversationId,
    String? customerId,
    MessageChannel? channel,
    MessageDirection? direction,
    String? content,
    String? contentHtml,
    DateTime? timestamp,
    String? subject,
    ChannelMetadata? channelMetadata,
    List<String>? bookingIds,
    List<String>? detectedBookingNumbers,
    AiDraft? aiDraft,
    List<SuggestedAction>? suggestedActions,
    MessageStatus? status,
    String? handledBy,
    DateTime? handledAt,
    bool? flaggedForReview,
    String? flagReason,
    MessagePriority? priority,
    String? sentiment,
    String? intent,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      customerId: customerId ?? this.customerId,
      channel: channel ?? this.channel,
      direction: direction ?? this.direction,
      content: content ?? this.content,
      contentHtml: contentHtml ?? this.contentHtml,
      timestamp: timestamp ?? this.timestamp,
      subject: subject ?? this.subject,
      channelMetadata: channelMetadata ?? this.channelMetadata,
      bookingIds: bookingIds ?? this.bookingIds,
      detectedBookingNumbers: detectedBookingNumbers ?? this.detectedBookingNumbers,
      aiDraft: aiDraft ?? this.aiDraft,
      suggestedActions: suggestedActions ?? this.suggestedActions,
      status: status ?? this.status,
      handledBy: handledBy ?? this.handledBy,
      handledAt: handledAt ?? this.handledAt,
      flaggedForReview: flaggedForReview ?? this.flaggedForReview,
      flagReason: flagReason ?? this.flagReason,
      priority: priority ?? this.priority,
      sentiment: sentiment ?? this.sentiment,
      intent: intent ?? this.intent,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

// Channel-specific metadata
class ChannelMetadata {
  final GmailMetadata? gmail;
  final WixMetadata? wix;
  final WhatsAppMetadata? whatsapp;

  ChannelMetadata({
    this.gmail,
    this.wix,
    this.whatsapp,
  });

  factory ChannelMetadata.fromJson(Map<String, dynamic> json) {
    return ChannelMetadata(
      gmail: json['gmail'] != null ? GmailMetadata.fromJson(json['gmail']) : null,
      wix: json['wix'] != null ? WixMetadata.fromJson(json['wix']) : null,
      whatsapp: json['whatsapp'] != null ? WhatsAppMetadata.fromJson(json['whatsapp']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gmail': gmail?.toJson(),
      'wix': wix?.toJson(),
      'whatsapp': whatsapp?.toJson(),
    };
  }
}

class GmailMetadata {
  final String threadId;
  final String messageId;
  final String from;
  final List<String> to;
  final List<String>? cc;

  GmailMetadata({
    required this.threadId,
    required this.messageId,
    required this.from,
    required this.to,
    this.cc,
  });

  factory GmailMetadata.fromJson(Map<String, dynamic> json) {
    return GmailMetadata(
      threadId: json['threadId'] ?? '',
      messageId: json['messageId'] ?? '',
      from: json['from'] ?? '',
      to: List<String>.from(json['to'] ?? []),
      cc: json['cc'] != null ? List<String>.from(json['cc']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'threadId': threadId,
      'messageId': messageId,
      'from': from,
      'to': to,
      'cc': cc,
    };
  }
}

class WixMetadata {
  final String visitorId;
  final String sessionId;

  WixMetadata({
    required this.visitorId,
    required this.sessionId,
  });

  factory WixMetadata.fromJson(Map<String, dynamic> json) {
    return WixMetadata(
      visitorId: json['visitorId'] ?? '',
      sessionId: json['sessionId'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'visitorId': visitorId,
      'sessionId': sessionId,
    };
  }
}

class WhatsAppMetadata {
  final String phoneNumber;
  final String messageId;

  WhatsAppMetadata({
    required this.phoneNumber,
    required this.messageId,
  });

  factory WhatsAppMetadata.fromJson(Map<String, dynamic> json) {
    return WhatsAppMetadata(
      phoneNumber: json['phoneNumber'] ?? '',
      messageId: json['messageId'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'phoneNumber': phoneNumber,
      'messageId': messageId,
    };
  }
}

// AI Draft response (Phase 2+)
class AiDraft {
  final String content;
  final double confidence;
  final String suggestedTone;
  final DateTime generatedAt;

  AiDraft({
    required this.content,
    required this.confidence,
    required this.suggestedTone,
    required this.generatedAt,
  });

  factory AiDraft.fromJson(Map<String, dynamic> json) {
    return AiDraft(
      content: json['content'] ?? '',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      suggestedTone: json['suggestedTone'] ?? 'friendly',
      generatedAt: Message._parseDateTime(json['generatedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'confidence': confidence,
      'suggestedTone': suggestedTone,
      'generatedAt': Timestamp.fromDate(generatedAt),
    };
  }
}

// Suggested action for Bokun integration (Phase 3+)
class SuggestedAction {
  final String type;
  final String bookingId;
  final Map<String, dynamic> currentState;
  final Map<String, dynamic> proposedState;
  final double confidence;
  final String reasoning;

  SuggestedAction({
    required this.type,
    required this.bookingId,
    required this.currentState,
    required this.proposedState,
    required this.confidence,
    required this.reasoning,
  });

  factory SuggestedAction.fromJson(Map<String, dynamic> json) {
    return SuggestedAction(
      type: json['type'] ?? '',
      bookingId: json['bookingId'] ?? '',
      currentState: Map<String, dynamic>.from(json['currentState'] ?? {}),
      proposedState: Map<String, dynamic>.from(json['proposedState'] ?? {}),
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      reasoning: json['reasoning'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'bookingId': bookingId,
      'currentState': currentState,
      'proposedState': proposedState,
      'confidence': confidence,
      'reasoning': reasoning,
    };
  }
}

