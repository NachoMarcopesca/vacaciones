import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/user_profile.dart';

class AuthRepository {
  static Future<UserProfile> fetchProfile(User user) async {
    final token = await user.getIdToken();
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/me');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Acceso no autorizado');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return UserProfile.fromJson(data);
  }
}
