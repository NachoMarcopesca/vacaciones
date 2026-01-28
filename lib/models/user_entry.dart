class UserEntry {
  final String userId;
  final String email;
  final String? displayName;
  final String? role;
  final String? departamentoId;
  final List<int> workingDays;

  const UserEntry({
    required this.userId,
    required this.email,
    this.displayName,
    this.role,
    this.departamentoId,
    this.workingDays = const [],
  });

  factory UserEntry.fromJson(Map<String, dynamic> json) {
    return UserEntry(
      userId: (json['userId'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      displayName: json['displayName']?.toString(),
      role: json['role']?.toString(),
      departamentoId: json['departamentoId']?.toString(),
      workingDays: _parseWorkingDays(json['workingDays']),
    );
  }

  static List<int> _parseWorkingDays(dynamic value) {
    if (value is! List) return const [];
    final items = <int>[];
    for (final entry in value) {
      final parsed = int.tryParse(entry.toString());
      if (parsed != null && parsed >= 1 && parsed <= 7) {
        items.add(parsed);
      }
    }
    return items;
  }
}
