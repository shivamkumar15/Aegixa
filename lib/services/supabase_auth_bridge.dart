import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

/// Bridges Firebase Auth identity into Supabase so that
/// `auth.uid()` in RLS policies matches the Firebase UID.
///
/// On every Firebase auth state change the bridge:
///   1. Fetches the Firebase ID token.
///   2. Calls the `firebase-auth-bridge` Edge Function to exchange it
///      for a Supabase-compatible JWT.
///   3. Sets the Supabase session using the returned token.
///
/// The token is refreshed automatically when it nears expiry.
class SupabaseAuthBridge {
  SupabaseAuthBridge._();
  static final SupabaseAuthBridge _instance = SupabaseAuthBridge._();
  factory SupabaseAuthBridge() => _instance;

  StreamSubscription<User?>? _authSubscription;
  Timer? _refreshTimer;
  bool _initialized = false;

  /// Guards against concurrent token exchanges (e.g. auth listener + manual
  /// syncSession firing at the same time).
  Completer<void>? _exchangeInFlight;

  /// Buffer before the Supabase token expires to trigger a refresh.
  static const _refreshBuffer = Duration(minutes: 5);

  /// Minimum interval between token exchange calls to avoid flooding.
  static const _minRefreshInterval = Duration(seconds: 30);
  DateTime? _lastRefreshAt;

  /// Start listening to Firebase auth state changes.
  /// Call once during app initialization (after Firebase & Supabase init).
  void initialize() {
    if (_initialized) return;
    _initialized = true;

    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen(_onAuthStateChanged);
  }

  /// Stop listening and clear any scheduled refresh.
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _initialized = false;
  }

  /// Exchange the current Firebase token for a Supabase session.
  /// Can be called manually (e.g. after sign-in) or automatically via
  /// the auth state listener.
  Future<void> syncSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await _clearSupabaseSession();
      return;
    }
    await _exchangeToken(user);
  }

  // ── Internals ─────────────────────────────────────────────────

  Future<void> _onAuthStateChanged(User? user) async {
    if (user == null) {
      await _clearSupabaseSession();
      return;
    }
    await _exchangeToken(user);
  }

  Future<void> _exchangeToken(User user) async {
    // If another exchange is already in flight, wait for it instead of
    // starting a duplicate network call.
    if (_exchangeInFlight != null) {
      await _exchangeInFlight!.future;
      return;
    }

    // Rate-limit to avoid multiple rapid calls.
    final now = DateTime.now();
    if (_lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < _minRefreshInterval) {
      return;
    }

    _exchangeInFlight = Completer<void>();
    try {
      final idToken = await user.getIdToken(true);
      if (idToken == null) {
        debugPrint('supabase-auth-bridge: Firebase ID token is null');
        return;
      }

      final response = await Supabase.instance.client.functions.invoke(
        'firebase-auth-bridge',
        body: {'firebaseToken': idToken},
      );

      if (response.status != 200) {
        debugPrint(
          'supabase-auth-bridge: token exchange failed '
          '(status ${response.status})',
        );
        return;
      }

      final data = response.data as Map<String, dynamic>?;
      final accessToken = data?['access_token'] as String?;
      final expiresAt = data?['expires_at'] as int?;

      if (accessToken == null || accessToken.isEmpty) {
        debugPrint('supabase-auth-bridge: no access_token in response');
        return;
      }

      // Set the Supabase session with the bridged token.
      // We use setSession which accepts an access token + refresh token.
      // Since we manage refresh ourselves (via Firebase), pass a dummy
      // refresh token — Supabase won't use it because we override before
      // expiry.
      await Supabase.instance.client.auth.setSession(accessToken);

      _lastRefreshAt = DateTime.now();
      debugPrint('supabase-auth-bridge: session synced for ${user.uid}');

      // Schedule proactive refresh before the token expires.
      _scheduleRefresh(expiresAt);
    } catch (e) {
      debugPrint('supabase-auth-bridge: exchange failed: $e');
    } finally {
      _exchangeInFlight?.complete();
      _exchangeInFlight = null;
    }
  }

  void _scheduleRefresh(int? expiresAtEpoch) {
    _refreshTimer?.cancel();

    if (expiresAtEpoch == null) return;

    final expiresAt =
        DateTime.fromMillisecondsSinceEpoch(expiresAtEpoch * 1000);
    final refreshAt = expiresAt.subtract(_refreshBuffer);
    final delay = refreshAt.difference(DateTime.now());

    if (delay.isNegative || delay.inSeconds < 30) {
      // Already close to expiry — refresh soon.
      _refreshTimer = Timer(const Duration(seconds: 30), syncSession);
    } else {
      _refreshTimer = Timer(delay, syncSession);
    }
  }

  Future<void> _clearSupabaseSession() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _lastRefreshAt = null;

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // Supabase may already be signed out — ignore.
    }
  }
}
