import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/balance_adjustment.dart';
import '../models/balance_entry.dart';
import '../models/vacation_balance.dart';

class BalancesRepository {
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

  static Future<VacationBalance> fetchBalance(String userId) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/balances/$userId');
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Error al cargar saldo');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final balanceJson = data['balance'] as Map<String, dynamic>? ?? {};
    return VacationBalance.fromJson(userId, balanceJson);
  }

  static Future<List<BalanceEntry>> fetchBalancesList() async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/balances');
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Error al cargar saldos');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((item) => BalanceEntry.fromJson(item as Map<String, dynamic>))
        .toList();
    return items;
  }

  static Future<void> adjustBalance({
    required String userId,
    int? diasAsignadosAnual,
    int? diasArrastrados,
    int? deltaExtra,
    String? comentario,
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/balances/$userId/adjust');
    final payload = jsonEncode({
      if (diasAsignadosAnual != null) 'diasAsignadosAnual': diasAsignadosAnual,
      if (diasArrastrados != null) 'diasArrastrados': diasArrastrados,
      if (deltaExtra != null) 'deltaExtra': deltaExtra,
      if (comentario != null) 'comentario': comentario,
    });

    final response = await http.post(uri, headers: headers, body: payload);
    if (response.statusCode != 200) {
      throw Exception('Error al actualizar saldo');
    }
  }

  static Future<List<BalanceAdjustment>> fetchAdjustments(String userId) async {
    final headers = await _authHeaders();
    final uri =
        Uri.parse('${AppConfig.backendBaseUrl}/balances/$userId/adjustments');
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Error al cargar ajustes');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((item) => BalanceAdjustment.fromJson(item as Map<String, dynamic>))
        .toList();
    return items;
  }
}
