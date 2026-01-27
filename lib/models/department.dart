class Department {
  final String id;
  final String name;
  final String? responsableId;

  const Department({
    required this.id,
    required this.name,
    this.responsableId,
  });

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      responsableId: json['responsableId']?.toString(),
    );
  }
}
