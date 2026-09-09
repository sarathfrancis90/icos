import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

part 'edge_function_client.g.dart';

/// Status + decoded JSON body of an edge function call. Non-2xx responses are
/// returned (not thrown) so callers can classify them; transport failures
/// (no network, timeout) still throw.
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

/// Default [EdgeInvoker] backed by the Supabase functions client.
Future<EdgeResponse> supabaseEdgeInvoke(
  String functionName,
  Map<String, dynamic> body,
) async {
  try {
    final response = await SupabaseService.functions
        .invoke(functionName, body: body)
        .timeout(const Duration(seconds: 20));
    return EdgeResponse(response.status, response.data as Object?);
  } on FunctionException catch (e) {
    return EdgeResponse(e.status, e.details as Object?);
  }
}

/// Overridable in tests to fake edge function responses.
@Riverpod(keepAlive: true)
EdgeInvoker edgeInvoker(Ref ref) => supabaseEdgeInvoke;
