import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/user_entry.dart';

class UsersRepository {
  static Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No autenticado');
    }
    final token = await user.getIdToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  static Future<List<UserEntry>> fetchUsers() async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/users');
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Error al cargar usuarios');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((item) => UserEntry.fromJson(item as Map<String, dynamic>))
        .toList();
    return items;
  }

  static Future<void> updateWorkingDays({
    required String userId,
    required List<int> workingDays,
  }) async {
    final headers = await _authHeaders();
    final uri =
        Uri.parse('${AppConfig.backendBaseUrl}/users/$userId/working-days');
    final payload = jsonEncode({'workingDays': workingDays});
    final response = await http.put(uri, headers: headers, body: payload);
    if (response.statusCode != 200) {
      throw Exception('Error al guardar horario');
    }
  }
}
