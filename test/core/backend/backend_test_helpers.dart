import 'dart:convert';

import 'package:icos/core/backend/backend_config.dart';

final testConfig = BackendConfig(
  apiBaseUrl: 'https://fn.example.test/',
  dataApiUrl: 'https://data.example.test/neondb/rest/v1',
);

/// Unsigned JWT-shaped token whose payload carries [exp].
String fakeJwt(DateTime exp, {String sub = 'u1'}) {
  String part(Map<String, Object?> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'ES256'})}.'
      '${part({'sub': sub, 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

Map<String, Object?> userJson({
  String id = 'u1',
  bool anonymous = false,
  String? email = 'a@b.co',
}) => {
  'id': id,
  'email': email,
  'emailVerified': false,
  'name': 'Ann',
  'isAnonymous': anonymous,
  'createdAt': '2026-11-08T00:00:00.000Z',
  'image': null,
};
