// User model for representing user data and roles 

class User {
  final String id;
  final String fullName;
  final String email;
  final String phoneNumber;
  final String role; // 'staff', 'guide', or 'admin'
  final String? profilePictureUrl;
  final DateTime createdAt;
  final bool isActive;
  final bool isAdmin;

  User({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.role,
    this.profilePictureUrl,
    required this.createdAt,
    this.isActive = true,
    this.isAdmin = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      fullName: json['fullName'] ?? '',
      email: json['email'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      role: json['role'] ?? 'staff',
      profilePictureUrl: json['profilePictureUrl'],
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      isActive: json['isActive'] ?? true,
      isAdmin: json['isAdmin'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'email': email,
      'phoneNumber': phoneNumber,
      'role': role,
      'profilePictureUrl': profilePictureUrl,
      'createdAt': createdAt.toIso8601String(),
      'isActive': isActive,
      'isAdmin': isAdmin,
    };
  }

  User copyWith({
    String? id,
    String? fullName,
    String? email,
    String? phoneNumber,
    String? role,
    String? profilePictureUrl,
    DateTime? createdAt,
    bool? isActive,
    bool? isAdmin,
  }) {
    return User(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role ?? this.role,
      profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }

  bool get isStaff => role == 'staff';
  bool get isGuide => role == 'guide';
} 