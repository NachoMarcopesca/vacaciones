import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

class HolidaysRepository {
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

  static Future<List<String>> fetchHolidays(int year) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/holidays')
        .replace(queryParameters: {'year': year.toString()});
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Error al cargar festivos');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((item) => (item as Map<String, dynamic>)['date']?.toString())
        .where((date) => date != null && date.isNotEmpty)
        .cast<String>()
        .toList();
    return items;
  }

  static Future<void> saveHolidays(int year, List<String> dates) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/holidays');
    final payload = jsonEncode({
      'year': year,
      'dates': dates,
    });

    final response = await http.put(uri, headers: headers, body: payload);
    if (response.statusCode != 200) {
      throw Exception('Error al guardar festivos');
    }
  }
}
