import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/department.dart';
import '../models/vacation_balance.dart';
import '../models/vacation_request.dart';

class RequestsRepository {
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

  static Future<List<VacationRequest>> fetchRequests({
    String? status,
    String? departamentoId,
    String? userId,
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/requests').replace(
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
        if (departamentoId != null && departamentoId.isNotEmpty)
          'departamentoId': departamentoId,
        if (userId != null && userId.isNotEmpty) 'userId': userId,
      },
    );

    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Error al cargar solicitudes');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((item) => VacationRequest.fromJson(item as Map<String, dynamic>))
        .toList();
    return items;
  }

  static Future<String> createRequest({
    required String fechaInicio,
    required String fechaFin,
    String? notas,
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/requests');
    final payload = jsonEncode({
      'fechaInicio': fechaInicio,
      'fechaFin': fechaFin,
      'notas': notas,
    });

    final response = await http.post(uri, headers: headers, body: payload);
    if (response.statusCode != 200) {
      throw Exception('Error al crear solicitud');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['id'] ?? '').toString();
  }

  static Future<void> updateRequest({
    required String id,
    required String fechaInicio,
    required String fechaFin,
    String? notas,
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/requests/$id');
    final payload = jsonEncode({
      'fechaInicio': fechaInicio,
      'fechaFin': fechaFin,
      'notas': notas,
    });

    final response = await http.patch(uri, headers: headers, body: payload);
    if (response.statusCode != 200) {
      throw Exception('Error al actualizar solicitud');
    }
  }

  static Future<void> approveRequest(String id) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/requests/$id/approve');
    final response = await http.post(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Error al aprobar solicitud');
    }
  }

  static Future<void> rejectRequest(String id) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/requests/$id/reject');
    final response = await http.post(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Error al rechazar solicitud');
    }
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

  static Future<List<VacationRequest>> fetchCalendar({
    required String from,
    required String to,
    List<String>? departamentoIds,
    bool includePending = false,
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/calendar').replace(
      queryParameters: {
        'from': from,
        'to': to,
        if (departamentoIds != null && departamentoIds.isNotEmpty)
          'departamentoIds': departamentoIds.join(','),
        if (includePending) 'includePending': '1',
      },
    );

    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Error al cargar calendario');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((item) => VacationRequest.fromJson(item as Map<String, dynamic>))
        .toList();
    return items;
  }

  static Future<List<Department>> fetchDepartments() async {
    final headers = await _authHeaders();
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/departments');
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Error al cargar departamentos');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((item) => Department.fromJson(item as Map<String, dynamic>))
        .toList();
    return items;
  }
}
