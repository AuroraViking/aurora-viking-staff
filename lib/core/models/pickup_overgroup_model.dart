/// Model for pickup place overgroups.
///
/// An overgroup unifies multiple pickup place names (that represent the
/// same physical location but are named differently by resellers) under
/// a single canonical display name.
class PickupOvergroup {
  final String id;
  final String name;
  final List<String> members;

  const PickupOvergroup({
    required this.id,
    required this.name,
    required this.members,
  });

  factory PickupOvergroup.fromMap(String id, Map<String, dynamic> data) {
    return PickupOvergroup(
      id: id,
      name: data['name'] as String? ?? '',
      members: List<String>.from(data['members'] as List? ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'members': members,
    };
  }

  PickupOvergroup copyWith({
    String? id,
    String? name,
    List<String>? members,
  }) {
    return PickupOvergroup(
      id: id ?? this.id,
      name: name ?? this.name,
      members: members ?? this.members,
    );
  }
}
