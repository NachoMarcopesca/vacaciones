enum UserRole {
  empleado,
  responsable,
  responsableGeneral,
  admin,
}

UserRole parseUserRole(String value) {
  switch (value.toLowerCase()) {
    case 'admin':
      return UserRole.admin;
    case 'responsable_general':
    case 'responsablegeneral':
      return UserRole.responsableGeneral;
    case 'responsable':
      return UserRole.responsable;
    case 'empleado':
    default:
      return UserRole.empleado;
  }
}

String userRoleToApi(UserRole role) {
  switch (role) {
    case UserRole.admin:
      return 'admin';
    case UserRole.responsableGeneral:
      return 'responsable_general';
    case UserRole.responsable:
      return 'responsable';
    case UserRole.empleado:
      return 'empleado';
  }
}
