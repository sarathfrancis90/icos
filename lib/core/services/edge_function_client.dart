import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../backend/backend_providers.dart';

part 'edge_function_client.g.dart';

/// Status + decoded JSON body of a server route call (`POST /api/<name>`).
/// Non-2xx responses are returned (not thrown) so callers can classify them;
/// transport failures (no network, timeout) still throw.
class EdgeResponse {
  const EdgeResponse(this.status, this.body);

  final int status;
  final Object? body;

  Map<String, dynamic>? get json =>
      body is Map<String, dynamic> ? body! as Map<String, dynamic> : null;

  /// `code` field of an error body, if any.
  String? get code => json?['code'] as String?;
}

typedef EdgeInvoker = Future<EdgeResponse> Function(
  String functionName,
  Map<String, dynamic> body,
);

/// The app's [EdgeInvoker], backed by [ApiClient.invoke]. The client is
/// resolved per call, so a missing backend configuration surfaces as a
/// thrown call (handled like a transport failure) rather than while the
/// providers that depend on this one are built. Overridable in tests to fake
/// server responses.
@Riverpod(keepAlive: true)
EdgeInvoker edgeInvoker(Ref ref) =>
    (name, body) => ref.read(apiClientProvider).invoke(name, body);
