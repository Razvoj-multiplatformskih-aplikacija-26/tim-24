import 'json.dart';

final class LoginRequestDto {
  const LoginRequestDto({
    required this.email,
    required this.password,
    this.browserSession = false,
    this.browserSessionScope = 'studio',
  });
  final String email, password, browserSessionScope;
  final bool browserSession;
  factory LoginRequestDto.fromJson(JsonObject json) => LoginRequestDto(
    email: string(json, 'email'),
    password: string(json, 'password'),
    browserSession: boolean(json, 'browserSession'),
    browserSessionScope: string(
      json,
      'browserSessionScope',
      fallback: 'studio',
    ),
  );
  JsonObject toJson() => {
    'email': email,
    'password': password,
    if (browserSession) 'browserSession': true,
    'browserSessionScope': browserSessionScope,
  };
}

final class RegisterRequestDto {
  const RegisterRequestDto({
    required this.email,
    required this.password,
    required this.displayName,
    this.browserSession = false,
    this.browserSessionScope = 'studio',
  });
  final String email, password, displayName, browserSessionScope;
  final bool browserSession;
  factory RegisterRequestDto.fromJson(JsonObject json) => RegisterRequestDto(
    email: string(json, 'email'),
    password: string(json, 'password'),
    displayName: string(json, 'displayName'),
    browserSession: boolean(json, 'browserSession'),
    browserSessionScope: string(
      json,
      'browserSessionScope',
      fallback: 'studio',
    ),
  );
  JsonObject toJson() => {
    'email': email,
    'password': password,
    'displayName': displayName,
    if (browserSession) 'browserSession': true,
    'browserSessionScope': browserSessionScope,
  };
}

final class RefreshRequestDto {
  const RefreshRequestDto({
    this.refreshToken,
    this.browserSession = false,
    this.browserSessionScope = 'studio',
  });
  final String? refreshToken;
  final bool browserSession;
  final String browserSessionScope;
  factory RefreshRequestDto.fromJson(JsonObject json) => RefreshRequestDto(
    refreshToken: optionalString(json, 'refreshToken'),
    browserSession: boolean(json, 'browserSession'),
    browserSessionScope: string(
      json,
      'browserSessionScope',
      fallback: 'studio',
    ),
  );
  JsonObject toJson() => {
    if (refreshToken != null) 'refreshToken': refreshToken,
    if (browserSession) 'browserSession': true,
    'browserSessionScope': browserSessionScope,
  };
}

final class IdentityDto {
  const IdentityDto({
    required this.id,
    required this.role,
    this.displayName = '',
    this.email = '',
  });
  final String id, role, displayName, email;
  factory IdentityDto.fromJson(JsonObject json) => IdentityDto(
    id: string(json, 'id'),
    role: string(json, 'role', fallback: 'creator'),
    displayName: string(json, 'displayName', fallback: ''),
    email: string(json, 'email', fallback: ''),
  );
  JsonObject toJson() => {
    'id': id,
    'role': role,
    'displayName': displayName,
    'email': email,
  };
}

final class SessionDto {
  const SessionDto({
    required this.token,
    required this.user,
    this.refreshToken,
    this.expiresAt,
    this.refreshExpiresAt,
  });
  final String token;
  final String? refreshToken;
  final IdentityDto user;
  final DateTime? expiresAt, refreshExpiresAt;
  factory SessionDto.fromJson(JsonObject json) => SessionDto(
    token: string(json, 'token'),
    refreshToken: optionalString(json, 'refreshToken'),
    user: IdentityDto.fromJson(object(json['user'])),
    expiresAt: optionalDate(json, 'expiresAt'),
    refreshExpiresAt: optionalDate(json, 'refreshExpiresAt'),
  );
  JsonObject toJson() => {
    'token': token,
    'user': user.toJson(),
    if (refreshToken != null) 'refreshToken': refreshToken,
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    if (refreshExpiresAt != null)
      'refreshExpiresAt': refreshExpiresAt!.toUtc().toIso8601String(),
  };
}
