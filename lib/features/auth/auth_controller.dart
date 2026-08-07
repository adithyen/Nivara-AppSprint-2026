import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/supabase_client.dart';
import '../../models/user_profile.dart';

/// Holds the signed-in user's [UserProfile] (with role), or `null` when signed
/// out. The whole app — including the router's redirect guard — reads auth
/// state through this one provider.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, UserProfile?>(AuthController.new);

class AuthController extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() async {
    // Safety net: if the session ends anywhere (expiry, another tab), reflect it.
    final sub = supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        state = const AsyncData(null);
      }
    });
    ref.onDispose(sub.cancel);

    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return null;
    return _fetchProfile(uid);
  }

  Future<UserProfile?> _fetchProfile(String uid) async {
    final row = await supabase
        .from(kTableProfiles)
        .select()
        .eq('id', uid)
        .maybeSingle();
    if (row == null) return null; // trigger creates it; tolerate a brief race
    return UserProfile.fromMap(row);
  }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      state = const AsyncData(null);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchProfile(uid));
  }

  /// Sign in with email + password. Throws [AuthException] on bad credentials —
  /// the caller shows the message.
  Future<void> signIn({required String email, required String password}) async {
    await supabase.auth.signInWithPassword(email: email, password: password);
    await _load();
  }

  /// Register a new citizen. `display_name` is passed as user metadata, which
  /// the `handle_new_user` trigger reads to seed the profile row.
  ///
  /// Returns `true` if a session was established immediately (email
  /// confirmation disabled). Returns `false` when the user must confirm their
  /// email before they can sign in.
  Future<bool> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final res = await supabase.auth.signUp(
      email: email,
      password: password,
      data: {'display_name': displayName},
    );
    if (res.session != null) {
      await _load();
      return true;
    }
    return false;
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
    state = const AsyncData(null);
  }

  /// Re-fetch the profile (e.g. after a role change or profile edit).
  Future<void> refresh() => _load();
}
