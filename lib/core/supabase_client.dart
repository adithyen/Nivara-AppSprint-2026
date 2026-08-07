import 'package:supabase_flutter/supabase_flutter.dart';

/// The single place the Supabase client is read from.
///
/// Per the architecture rules, never call `Supabase.instance.client` directly
/// anywhere else — always go through this accessor so the dependency is easy to
/// track and swap in tests.
SupabaseClient get supabase => Supabase.instance.client;

/// Convenience: the currently signed-in auth user, or `null`.
User? get currentUser => supabase.auth.currentUser;

/// Convenience: the current user's id, or `null` when signed out.
String? get currentUserId => supabase.auth.currentUser?.id;
