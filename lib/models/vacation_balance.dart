class VacationBalance {
  final String userId;
  final int diasAsignadosAnual;
  final int diasArrastrados;
  final int diasConsumidos;
  final int diasDisponibles;

  const VacationBalance({
    required this.userId,
    required this.diasAsignadosAnual,
    required this.diasArrastrados,
    required this.diasConsumidos,
    required this.diasDisponibles,
  });

  factory VacationBalance.fromJson(String userId, Map<String, dynamic> json) {
    int _parse(dynamic value) {
      if (value is int) return value;
      return int.tryParse((value ?? '0').toString()) ?? 0;
    }

    return VacationBalance(
      userId: userId,
      diasAsignadosAnual: _parse(json['diasAsignadosAnual']),
      diasArrastrados: _parse(json['diasArrastrados']),
      diasConsumidos: _parse(json['diasConsumidos']),
      diasDisponibles: _parse(json['diasDisponibles']),
    );
  }
}
