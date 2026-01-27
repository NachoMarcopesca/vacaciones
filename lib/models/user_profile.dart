import 'user_role.dart';

class UserProfile {
  final String uid;
  final String email;
  final UserRole role;
  final String? departamentoId;
  final String? displayName;

  const UserProfile({
    required this.uid,
    required this.email,
    required this.role,
    this.departamentoId,
    this.displayName,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      uid: (json['uid'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      role: parseUserRole((json['role'] ?? '').toString()),
      departamentoId: json['departamentoId']?.toString(),
      displayName: json['displayName']?.toString(),
    );
  }
}
