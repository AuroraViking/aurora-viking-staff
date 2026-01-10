// Customer model for the Unified Inbox system
// Represents a customer across all communication channels

import 'package:cloud_firestore/cloud_firestore.dart';

class Customer {
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final CustomerChannels channels;
  final String? bokunCustomerId;
  final int totalBookings;
  final List<String> upcomingBookings;
  final List<String> pastBookings;
  final String? preferredChannel;
  final String language;
  final bool vipStatus;
  final int pastInteractions;
  final int averageResponseTime;
  final List<String> commonRequests;
  final DateTime firstContact;
  final DateTime lastContact;
  final DateTime createdAt;
  final DateTime updatedAt;

  Customer({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    required this.channels,
    this.bokunCustomerId,
    this.totalBookings = 0,
    this.upcomingBookings = const [],
    this.pastBookings = const [],
    this.preferredChannel,
    this.language = 'en',
    this.vipStatus = false,
    this.pastInteractions = 0,
    this.averageResponseTime = 0,
    this.commonRequests = const [],
    required this.firstContact,
    required this.lastContact,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'],
      phone: json['phone'],
      channels: CustomerChannels.fromJson(json['channels'] ?? {}),
      bokunCustomerId: json['bokunCustomerId'],
      totalBookings: json['totalBookings'] ?? 0,
      upcomingBookings: List<String>.from(json['upcomingBookings'] ?? []),
      pastBookings: List<String>.from(json['pastBookings'] ?? []),
      preferredChannel: json['preferredChannel'],
      language: json['language'] ?? 'en',
      vipStatus: json['vipStatus'] ?? false,
      pastInteractions: json['pastInteractions'] ?? 0,
      averageResponseTime: json['averageResponseTime'] ?? 0,
      commonRequests: List<String>.from(json['commonRequests'] ?? []),
      firstContact: _parseDateTime(json['firstContact']) ?? DateTime.now(),
      lastContact: _parseDateTime(json['lastContact']) ?? DateTime.now(),
      createdAt: _parseDateTime(json['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDateTime(json['updatedAt']) ?? DateTime.now(),
    );
  }

  factory Customer.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Customer.fromJson({
      ...data,
      'id': doc.id,
    });
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'channels': channels.toJson(),
      'bokunCustomerId': bokunCustomerId,
      'totalBookings': totalBookings,
      'upcomingBookings': upcomingBookings,
      'pastBookings': pastBookings,
      'preferredChannel': preferredChannel,
      'language': language,
      'vipStatus': vipStatus,
      'pastInteractions': pastInteractions,
      'averageResponseTime': averageResponseTime,
      'commonRequests': commonRequests,
      'firstContact': Timestamp.fromDate(firstContact),
      'lastContact': Timestamp.fromDate(lastContact),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Customer copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    CustomerChannels? channels,
    String? bokunCustomerId,
    int? totalBookings,
    List<String>? upcomingBookings,
    List<String>? pastBookings,
    String? preferredChannel,
    String? language,
    bool? vipStatus,
    int? pastInteractions,
    int? averageResponseTime,
    List<String>? commonRequests,
    DateTime? firstContact,
    DateTime? lastContact,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      channels: channels ?? this.channels,
      bokunCustomerId: bokunCustomerId ?? this.bokunCustomerId,
      totalBookings: totalBookings ?? this.totalBookings,
      upcomingBookings: upcomingBookings ?? this.upcomingBookings,
      pastBookings: pastBookings ?? this.pastBookings,
      preferredChannel: preferredChannel ?? this.preferredChannel,
      language: language ?? this.language,
      vipStatus: vipStatus ?? this.vipStatus,
      pastInteractions: pastInteractions ?? this.pastInteractions,
      averageResponseTime: averageResponseTime ?? this.averageResponseTime,
      commonRequests: commonRequests ?? this.commonRequests,
      firstContact: firstContact ?? this.firstContact,
      lastContact: lastContact ?? this.lastContact,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Get display name (name or email or phone)
  String get displayName {
    if (name.isNotEmpty) return name;
    if (email != null && email!.isNotEmpty) return email!;
    if (phone != null && phone!.isNotEmpty) return phone!;
    return 'Unknown Customer';
  }

  /// Get initials for avatar
  String get initials {
    final words = name.trim().split(' ');
    if (words.length >= 2) {
      return '${words.first[0]}${words.last[0]}'.toUpperCase();
    } else if (name.isNotEmpty) {
      return name[0].toUpperCase();
    }
    return '?';
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

class CustomerChannels {
  final String? gmail;
  final String? whatsapp;
  final String? wix;

  CustomerChannels({
    this.gmail,
    this.whatsapp,
    this.wix,
  });

  factory CustomerChannels.fromJson(Map<String, dynamic> json) {
    return CustomerChannels(
      gmail: json['gmail'],
      whatsapp: json['whatsapp'],
      wix: json['wix'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gmail': gmail,
      'whatsapp': whatsapp,
      'wix': wix,
    };
  }

  /// Check if customer has any channel
  bool get hasAnyChannel => gmail != null || whatsapp != null || wix != null;

  /// Get the primary contact info based on available channels
  String? get primaryContact => gmail ?? whatsapp ?? wix;
}

