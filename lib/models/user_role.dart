enum UserRole {
  empleado,
  responsable,
  jefe,
  adminSistema,
}

UserRole parseUserRole(String value) {
  switch (value.toLowerCase()) {
    case 'admin_sistema':
      return UserRole.adminSistema;
    case 'admin':
      return UserRole.adminSistema;
    case 'jefe':
      return UserRole.jefe;
    case 'responsable_general':
    case 'responsablegeneral':
      return UserRole.jefe;
    case 'responsable':
      return UserRole.responsable;
    case 'empleado':
    default:
      return UserRole.empleado;
  }
}

String userRoleToApi(UserRole role) {
  switch (role) {
    case UserRole.adminSistema:
      return 'admin_sistema';
    case UserRole.jefe:
      return 'jefe';
    case UserRole.responsable:
      return 'responsable';
    case UserRole.empleado:
      return 'empleado';
  }
}
