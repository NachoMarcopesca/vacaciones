class BalanceAdjustment {
  final String id;
  final String userId;
  final int deltaExtra;
  final String? comentario;
  final String? createdBy;
  final String? createdAt;

  const BalanceAdjustment({
    required this.id,
    required this.userId,
    required this.deltaExtra,
    this.comentario,
    this.createdBy,
    this.createdAt,
  });

  factory BalanceAdjustment.fromJson(Map<String, dynamic> json) {
    int _parse(dynamic value) {
      if (value is int) return value;
      return int.tryParse((value ?? '0').toString()) ?? 0;
    }

    return BalanceAdjustment(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      deltaExtra: _parse(json['deltaExtra']),
      comentario: json['comentario']?.toString(),
      createdBy: json['createdBy']?.toString(),
      createdAt: json['createdAt']?.toString(),
    );
  }
}
