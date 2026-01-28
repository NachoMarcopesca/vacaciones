class BalanceEntry {
  final String userId;
  final String email;
  final String? displayName;
  final String? departamentoId;
  final int diasAsignadosAnual;
  final int diasArrastrados;
  final int diasExtra;
  final int diasConsumidos;
  final int diasDisponibles;
  final String? lastExtraComentario;
  final int lastExtraDelta;
  final String? lastExtraBy;
  final String? lastExtraAt;

  const BalanceEntry({
    required this.userId,
    required this.email,
    this.displayName,
    this.departamentoId,
    required this.diasAsignadosAnual,
    required this.diasArrastrados,
    required this.diasExtra,
    required this.diasConsumidos,
    required this.diasDisponibles,
    this.lastExtraComentario,
    this.lastExtraDelta = 0,
    this.lastExtraBy,
    this.lastExtraAt,
  });

  factory BalanceEntry.fromJson(Map<String, dynamic> json) {
    int _parse(dynamic value) {
      if (value is int) return value;
      return int.tryParse((value ?? '0').toString()) ?? 0;
    }

    return BalanceEntry(
      userId: (json['userId'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      displayName: json['displayName']?.toString(),
      departamentoId: json['departamentoId']?.toString(),
      diasAsignadosAnual: _parse(json['diasAsignadosAnual']),
      diasArrastrados: _parse(json['diasArrastrados']),
      diasExtra: _parse(json['diasExtra']),
      diasConsumidos: _parse(json['diasConsumidos']),
      diasDisponibles: _parse(json['diasDisponibles']),
      lastExtraComentario: json['lastExtraComentario']?.toString(),
      lastExtraDelta: _parse(json['lastExtraDelta']),
      lastExtraBy: json['lastExtraBy']?.toString(),
      lastExtraAt: json['lastExtraAt']?.toString(),
    );
  }
}
