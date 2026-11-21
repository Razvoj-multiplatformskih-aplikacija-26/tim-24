/// A platform adapter stores this credential bundle without storing a password.
final class StoredSession {
  StoredSession({
    required this.token,
    required this.refreshToken,
    required Map<String, dynamic> user,
    this.expiresAt,
    this.refreshExpiresAt,
  }) : user = Map.unmodifiable(user);

  final String token;
  final String? refreshToken;
  final Map<String, dynamic> user;
  final DateTime? expiresAt, refreshExpiresAt;

  factory StoredSession.fromJson(Map<String, dynamic> json) => StoredSession(
    token: json['token'] as String,
    refreshToken: json['refreshToken'] as String?,
    user: Map<String, dynamic>.from(json['user'] as Map),
    expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
    refreshExpiresAt: DateTime.tryParse(
      json['refreshExpiresAt'] as String? ?? '',
    ),
  );

  Map<String, dynamic> toJson() => {
    'token': token,
    'refreshToken': refreshToken,
    'user': user,
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    if (refreshExpiresAt != null)
      'refreshExpiresAt': refreshExpiresAt!.toUtc().toIso8601String(),
  };
}

/// Native clients implement this port with the operating system's secure store.
/// Browser clients use the server's HttpOnly refresh cookie instead.
abstract interface class SessionStorage {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}
