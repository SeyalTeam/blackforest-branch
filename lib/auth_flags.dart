bool _toBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'y' ||
        normalized == 'on';
  }
  return false;
}

bool isLoginBlockedUser(dynamic user) {
  if (user is! Map) return false;
  return _toBool(user['loginBlocked']) || _toBool(user['loginblocked']);
}

bool isForceLoggedOutUser(dynamic user) {
  if (user is! Map) return false;

  const forceLogoutKeys = [
    'forceLogoutAllDevices',
    'forceLogout',
    'forcelogout',
    'forceLogoutAll',
    'forcelogot',
  ];

  for (final key in forceLogoutKeys) {
    if (_toBool(user[key])) return true;
  }
  return false;
}
