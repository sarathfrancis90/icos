import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icos/core/services/edge_function_client.dart';
import 'package:postgrest/postgrest.dart';

/// Base URL the Data API test clients point at.
const testDataApiUrl = 'https://ep-test.apirest.example.test/neondb/rest/v1';

/// A real [PostgrestClient] against an in-memory HTTP handler, so code is
/// exercised through PostgREST's actual request/response and error handling.
PostgrestClient testDataApi(
  Future<http.Response> Function(http.Request request) handler,
) => PostgrestClient(
  testDataApiUrl,
  // PostgREST reads `response.request`, which MockClient leaves unset.
  httpClient: MockClient((request) async {
    final r = await handler(request);
    return http.Response(
      r.body,
      r.statusCode,
      headers: r.headers,
      request: request,
    );
  }),
);

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// One recorded [EdgeInvoker] call.
typedef RouteCall = ({String name, Map<String, dynamic> body});

/// [EdgeInvoker] fake that records calls and answers with [respond].
class FakeRoutes {
  FakeRoutes([EdgeResponse Function(String name, Map<String, dynamic> body)? respond])
    : _respond = respond ?? ((_, _) => const EdgeResponse(200, {}));

  final EdgeResponse Function(String name, Map<String, dynamic> body) _respond;
  final calls = <RouteCall>[];

  Future<EdgeResponse> invoke(String name, Map<String, dynamic> body) async {
    calls.add((name: name, body: body));
    return _respond(name, body);
  }
}

/// [PostgrestClientGetter] for fakes that override every data method.
PostgrestClient unusedDataApi() =>
    throw StateError('this fake does not reach the Data API');

/// [EdgeInvoker] for fakes that override every route method.
Future<EdgeResponse> unusedInvoker(String name, Map<String, dynamic> body) =>
    throw StateError('this fake does not call /api/$name');
