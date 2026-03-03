import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  static GoTrueClient get auth => client.auth;
  static SupabaseQueryBuilder Function(String table) get from => client.from;
  static RealtimeClient get realtime => client.realtime;
  static SupabaseStorageClient get storage => client.storage;
  static FunctionsClient get functions => client.functions;
}
