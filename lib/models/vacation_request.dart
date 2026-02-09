class VacationRequest {
  final String id;
  final String? userId;
  final String? userEmail;
  final String? userDisplayName;
  final String? userRole;
  final String? departamentoId;
  final String tipo;
  final String? fechaInicioStr;
  final String? fechaFinStr;
  final String estado;
  final String? aprobadorId;
  final String? fechaAprobacion;
  final String? notas;
  final int diasConsumidos;
  final int diasEstimados;
  final List<int> workingDays;

  const VacationRequest({
    required this.id,
    required this.tipo,
    required this.estado,
    this.userId,
    this.userEmail,
    this.userDisplayName,
    this.userRole,
    this.departamentoId,
    this.fechaInicioStr,
    this.fechaFinStr,
    this.aprobadorId,
    this.fechaAprobacion,
    this.notas,
    this.diasConsumidos = 0,
    this.diasEstimados = 0,
    this.workingDays = const [],
  });

  factory VacationRequest.fromJson(Map<String, dynamic> json) {
    return VacationRequest(
      id: (json['id'] ?? '').toString(),
      userId: json['userId']?.toString(),
      userEmail: json['userEmail']?.toString(),
      userDisplayName: json['userDisplayName']?.toString(),
      userRole: json['userRole']?.toString(),
      departamentoId: json['departamentoId']?.toString(),
      tipo: (json['tipo'] ?? 'vacaciones').toString(),
      fechaInicioStr: json['fechaInicioStr']?.toString(),
      fechaFinStr: json['fechaFinStr']?.toString(),
      estado: (json['estado'] ?? 'pendiente').toString(),
      aprobadorId: json['aprobadorId']?.toString(),
      fechaAprobacion: json['fechaAprobacion']?.toString(),
      notas: json['notas']?.toString(),
      diasConsumidos: (json['diasConsumidos'] ?? 0) is int
          ? (json['diasConsumidos'] ?? 0) as int
          : int.tryParse((json['diasConsumidos'] ?? '0').toString()) ?? 0,
      diasEstimados: (json['diasEstimados'] ?? 0) is int
          ? (json['diasEstimados'] ?? 0) as int
          : int.tryParse((json['diasEstimados'] ?? '0').toString()) ?? 0,
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

  Map<String, dynamic> toCreatePayload() {
    return {
      'fechaInicio': fechaInicioStr,
      'fechaFin': fechaFinStr,
      'notas': notas,
    };
  }

  Map<String, dynamic> toUpdatePayload() {
    return {
      'fechaInicio': fechaInicioStr,
      'fechaFin': fechaFinStr,
      'notas': notas,
    };
  }
}
