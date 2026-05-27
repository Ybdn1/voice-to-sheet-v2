class AuthSession {
  AuthSession({
    required this.accessToken,
    required this.username,
    required this.fullName,
    required this.role,
  });

  final String accessToken;
  final String username;
  final String fullName;
  final String role;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return AuthSession(
      accessToken: json['access_token'] as String? ?? '',
      username: user['username'] as String? ?? '',
      fullName: user['full_name'] as String? ?? '',
      role: user['role'] as String? ?? '',
    );
  }
}
