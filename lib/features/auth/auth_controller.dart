import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/services/app_lock_service.dart';
import '../../core/services/debug_logger.dart';
import '../../core/supabase_client.dart';
import '../../models/enums.dart';
import '../../models/user_profile.dart';

const _kProfileCachePrefix = 'cached_user_profile_';

/// Holds the signed-in user's [UserProfile] (with role), or `null` when signed
/// out. The whole app — including the router's redirect guard — reads auth
/// state through this one provider.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, UserProfile?>(AuthController.new);

class AuthController extends AsyncNotifier<UserProfile?> {
  static final _log = DebugLogger.instance;

  @override
  Future<UserProfile?> build() async {
    // Listen to all auth state changes (OAuth redirects, session expiry, token refresh).
    final sub = supabase.auth.onAuthStateChange.listen((data) async {
      _log.log('AUTH', 'onAuthStateChange event: ${data.event}');
      if (data.event == AuthChangeEvent.signedOut) {
        _clearCachedProfile();
        state = const AsyncData(null);
      } else if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.tokenRefreshed ||
          data.event == AuthChangeEvent.userUpdated) {
        await _load();
        // Clear external auth in progress after routes settle
        Future.delayed(const Duration(seconds: 3), () {
          AppLockService.instance.isExternalAuthInProgress = false;
        });
      }
    });
    ref.onDispose(sub.cancel);

    final user = supabase.auth.currentUser;
    if (user == null) return null;
    final uid = user.id;

    // 1. Immediately read from local cache if available (instant offline boot)
    final cached = await _getCachedProfile(uid);

    // 2. Fetch fresh profile asynchronously with timeout
    unawaited(_refreshInBackground(uid, user));

    if (cached != null) {
      return cached;
    }

    // 3. If no cache yet, attempt fast fetch or construct offline fallback
    try {
      final remote = await _fetchProfile(uid).timeout(const Duration(seconds: 3));
      if (remote != null) {
        await _saveCachedProfile(remote);
        return remote;
      }
    } catch (e) {
      _log.log('AUTH', 'Offline or fetch failed on startup: $e');
    }

    // 4. Construct offline fallback from session user metadata so app never hangs
    final fallback = UserProfile(
      id: uid,
      displayName: (user.userMetadata?['display_name'] as String?) ??
          user.email?.split('@').first ??
          'Citizen',
      phone: user.phone,
      role: UserRole.citizen,
    );
    await _saveCachedProfile(fallback);
    return fallback;
  }

  Future<void> _refreshInBackground(String uid, User user) async {
    try {
      final remote = await _fetchProfile(uid).timeout(const Duration(seconds: 4));
      if (remote != null) {
        await _saveCachedProfile(remote);
        state = AsyncData(remote);
      }
    } catch (e) {
      _log.log('AUTH', 'Background profile sync skipped (offline/error): $e');
    }
  }

  Future<UserProfile?> _fetchProfile(String uid) async {
    try {
      final row = await supabase
          .from(kTableProfiles)
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return null;
      return UserProfile.fromMap(row);
    } catch (e) {
      _log.error('AUTH', 'Profile fetch error: $e');
      return null;
    }
  }

  Future<UserProfile?> _getCachedProfile(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_kProfileCachePrefix$uid');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return UserProfile.fromMap(map);
      }
    } catch (e) {
      _log.error('AUTH', 'Failed to read cached profile: $e');
    }
    return null;
  }

  Future<void> _saveCachedProfile(UserProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_kProfileCachePrefix${profile.id}',
        jsonEncode(profile.toMap()),
      );
    } catch (e) {
      _log.error('AUTH', 'Failed to save cached profile: $e');
    }
  }

  Future<void> _clearCachedProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = supabase.auth.currentUser?.id;
      if (uid != null) {
        await prefs.remove('$_kProfileCachePrefix$uid');
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      state = const AsyncData(null);
      return;
    }
    final uid = user.id;

    final profile = await _fetchProfile(uid);
    if (profile != null) {
      await _saveCachedProfile(profile);
      state = AsyncData(profile);
      return;
    }

    final cached = await _getCachedProfile(uid);
    if (cached != null) {
      state = AsyncData(cached);
      return;
    }

    // Google OAuth first login: construct fallback profile so user is instantly signed in
    final metaName = (user.userMetadata?['full_name'] as String?) ??
        (user.userMetadata?['name'] as String?) ??
        (user.userMetadata?['display_name'] as String?) ??
        user.email?.split('@').first ??
        'Citizen';
    final fallback = UserProfile(
      id: uid,
      displayName: metaName,
      phone: user.phone,
      role: UserRole.citizen,
    );
    await _saveCachedProfile(fallback);
    state = AsyncData(fallback);

    // Persist profile row in Supabase in background
    try {
      await supabase.from(kTableProfiles).upsert({
        'id': uid,
        'display_name': metaName,
        'role': 'citizen',
      });
    } catch (_) {}
  }

  /// Sign in with email + password.
  Future<void> signIn({required String email, required String password}) async {
    await supabase.auth.signInWithPassword(email: email, password: password);
    await _load();
  }

  /// Sign in using Google OAuth via Supabase.
  Future<bool> signInWithGoogle() async {
    AppLockService.instance.isExternalAuthInProgress = true;
    try {
      final res = await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'in.adithyen.nivara://login-callback',
      );
      if (res) {
        await _load();
      }
      return res;
    } catch (e) {
      AppLockService.instance.isExternalAuthInProgress = false;
      rethrow;
    }
  }

  /// Register a new citizen.
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
    await _clearCachedProfile();
    await supabase.auth.signOut();
    state = const AsyncData(null);
  }

  /// Re-fetch the profile (e.g. after a role change or profile edit).
  Future<void> refresh() => _load();
}
