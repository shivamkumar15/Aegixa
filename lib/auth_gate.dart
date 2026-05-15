import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/emergency_contacts_setup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/username_setup_screen.dart';
import 'screens/verify_email_screen.dart';
import 'services/emergency_contacts_service.dart';
import 'services/sos_trigger_cache_service.dart';
import 'services/username_service.dart';

import 'ui_components.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Cached routing future keyed by UID so we don't re-fire network requests
  /// on every StreamBuilder rebuild.
  String? _cachedUid;
  Future<_RoutingDecision>? _cachedRoutingFuture;

  /// Returns a cached future for [uid], only creating a new one when the UID
  /// changes (i.e. a different user signs in).
  Future<_RoutingDecision> _getRoutingFuture(String uid) {
    if (_cachedUid != uid || _cachedRoutingFuture == null) {
      _cachedUid = uid;
      _cachedRoutingFuture = _resolveRouting(uid);
    }
    return _cachedRoutingFuture!;
  }

  /// Runs username lookup, profile-completeness check, and onboarding check
  /// **in parallel** instead of sequentially.  This cuts the visible loading
  /// time from 3 serial round-trips down to one parallel batch.
  Future<_RoutingDecision> _resolveRouting(String uid) async {
    unawaited(SosTriggerCacheService().warmup());

    // ── Fast path ──────────────────────────────────────────────────────
    // If the user previously completed all setup steps (username, profile
    // details, onboarding), skip network checks entirely for instant
    // startup.  This eliminates the 2-second timeout window that causes
    // offline users to land on the setup screen by mistake.
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('routing_setup_complete_$uid') ?? false) {
        return _RoutingDecision(
          username: uid, // non-empty → passes hasUsername check
          hasProfileDetails: true,
          shouldShowOnboarding: false,
        );
      }
    } catch (_) {
      // SharedPreferences failure — fall through to normal path.
    }

    // ── Normal path (first-time / re-verification) ────────────────────
    try {
      final results = await Future.wait([
        UsernameService().getUsernameForUserId(uid).timeout(
          const Duration(seconds: 2),
          onTimeout: () => null,
        ),
        _hasProfileDetails(uid).timeout(
          const Duration(seconds: 2),
          onTimeout: () => false,
        ),
        EmergencyContactsService().shouldShowOnboarding().timeout(
          const Duration(seconds: 2),
          onTimeout: () => true,
        ),
      ]);

      final decision = _RoutingDecision(
        username: results[0] as String?,
        hasProfileDetails: results[1] as bool,
        shouldShowOnboarding: results[2] as bool,
      );

      // Persist completion flag so future launches skip network checks.
      final hasUsername =
          (decision.username ?? '').trim().isNotEmpty;
      if (hasUsername &&
          decision.hasProfileDetails &&
          !decision.shouldShowOnboarding) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('routing_setup_complete_$uid', true);
        } catch (_) {}
      }

      return decision;
    } catch (_) {
      return const _RoutingDecision(
        username: null,
        hasProfileDetails: true,
        shouldShowOnboarding: false,
        networkUnavailable: true,
      );
    }
  }

  Future<bool> _hasProfileDetails(String uid) async {
    final profile = await UsernameService().getPublicProfileForUserId(uid);
    if (profile == null) {
      return false;
    }

    // While we have the profile, cache the photo path so HomeScreen doesn't
    // need to make another round-trip to Supabase just for the avatar.
    final photoPath = (profile.profilePhotoPath ?? '').trim();
    if (photoPath.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profile_photo_$uid', photoPath);
      } catch (_) {
        // Non-critical; HomeScreen will fetch if cache is empty.
      }
    }

    // Require only phone number to consider profile complete.
    // date_of_birth may fail to persist if the column is missing from the
    // Supabase table, so we must not gate the entire app on it.
    final phone = (profile.phoneNumber ?? '').trim();
    return phone.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _loadingScaffold(context);
        }

        if (!snapshot.hasData) {
          // Clear cached future when user signs out.
          _cachedUid = null;
          _cachedRoutingFuture = null;
          return const LoginScreen();
        }

        final user = snapshot.data!;

        // Determine session validity based on the *primary* sign-in method,
        // not just any linked provider.  This prevents an attacker from
        // bypassing email verification by linking a phone number they control.
        final providers =
            user.providerData.map((p) => p.providerId).toSet();
        final hasEmailPasswordProvider = providers.contains('password');
        final hasOAuthProvider = providers.contains('google.com') ||
            providers.contains('apple.com');
        // Phone-only accounts (no email/password provider) are allowed
        // because the user proved possession via OTP.
        final hasPhoneOnlyAuth =
            providers.contains('phone') && !hasEmailPasswordProvider;

        final isAllowedSession =
            hasOAuthProvider || hasPhoneOnlyAuth || user.emailVerified;

        if (!isAllowedSession) {
          return const VerifyEmailScreen();
        }

        return FutureBuilder<_RoutingDecision>(
          future: _getRoutingFuture(user.uid),
          builder: (context, routingSnapshot) {
            if (routingSnapshot.connectionState ==
                ConnectionState.waiting) {
              return _loadingScaffold(context);
            }

            final decision = routingSnapshot.data;
            if (decision == null) {
              // Future completed with an error — fall back to loading.
              return _loadingScaffold(context);
            }

            final hasUsername =
                (decision.username ?? '').trim().isNotEmpty;

            if (decision.networkUnavailable) {
              // When offline, only allow access to HomeScreen if the user
              // has previously completed setup (username cached locally).
              // Otherwise force them to retry when connectivity returns.
              if (hasUsername) {
                return const HomeScreen(showOfflineBanner: true);
              }
              // No cached username and no network — show a retry screen
              // instead of granting access without profile completion.
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off, size: 64),
                        const SizedBox(height: 16),
                        const Text(
                          'No internet connection',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Please connect to the internet to complete your profile setup.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _cachedUid = null;
                              _cachedRoutingFuture = null;
                            });
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            if (!hasUsername || !decision.hasProfileDetails) {
              return UsernameSetupScreen(
                user: user,
                prefilledUsername:
                    hasUsername ? decision.username : null,
              );
            }

            if (decision.shouldShowOnboarding) {
              return const EmergencyContactsSetupScreen();
            }

            return const HomeScreen();
          },
        );
      },
    );
  }

  Widget _loadingScaffold(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SailorLoader(),
      ),
    );
  }
}

class _RoutingDecision {
  const _RoutingDecision({
    required this.username,
    required this.hasProfileDetails,
    required this.shouldShowOnboarding,
    this.networkUnavailable = false,
  });

  final String? username;
  final bool hasProfileDetails;
  final bool shouldShowOnboarding;
  final bool networkUnavailable;
}
