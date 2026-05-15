import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    hide OAuthProvider, User;

class AuthService {
  AuthService._();
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const Duration _verificationEmailCooldown = Duration(seconds: 60);
  DateTime? _lastVerificationEmailSentAt;

  // ── Current user ──────────────────────────────────────────────
  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  int get verificationEmailCooldownRemainingSeconds {
    final lastSentAt = _lastVerificationEmailSentAt;
    if (lastSentAt == null) return 0;

    final elapsed = DateTime.now().difference(lastSentAt);
    final remaining = _verificationEmailCooldown - elapsed;
    return remaining.isNegative ? 0 : remaining.inSeconds + 1;
  }

  Future<void> sendVerificationEmailWithRateLimit(User? user) async {
    if (user == null) return;

    final remaining = verificationEmailCooldownRemainingSeconds;
    if (remaining > 0) {
      throw FirebaseAuthException(
        code: 'verification-email-rate-limited',
        message: 'Please wait $remaining seconds before requesting again.',
      );
    }

    await user.sendEmailVerification();
    _lastVerificationEmailSentAt = DateTime.now();
  }

  // ── Email & Password ─────────────────────────────────────────
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    await credential.user?.updateDisplayName(fullName);

    try {
      await sendVerificationEmailWithRateLimit(credential.user);
    } on FirebaseAuthException {
      rethrow;
    }
    return credential;
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    await credential.user?.reload();
    final isVerified = credential.user?.emailVerified ?? false;
    if (!isVerified) {
      try {
        await sendVerificationEmailWithRateLimit(credential.user);
      } catch (_) {
        // Keep flow secure even if resend fails; user stays blocked.
      }
      throw FirebaseAuthException(
        code: 'email-not-verified',
        message: 'Please verify your email before signing in.',
      );
    }

    return credential;
  }

  // ── Phone (OTP) ──────────────────────────────────────────────
  Future<void> signInWithPhone({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(PhoneAuthCredential credential) onAutoVerified,
    required void Function(FirebaseAuthException error) onError,
    int? forceResendingToken,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      forceResendingToken: forceResendingToken,
      verificationCompleted: (PhoneAuthCredential credential) {
        onAutoVerified(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        onError(e);
      },
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        // Auto-retrieval timed out — user must enter code manually
      },
    );
  }

  Future<UserCredential> verifyOTP({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final userCredential = await _auth.signInWithCredential(credential);
    return userCredential;
  }

  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    return _auth.signInWithCredential(credential);
  }

  // ── Google Sign-In ───────────────────────────────────────────
  Future<UserCredential> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'cancelled',
        message: 'Google sign-in was cancelled.',
      );
    }

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return _auth.signInWithCredential(credential);
  }

  // ── Apple Sign-In (iOS) ──────────────────────────────────────
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<UserCredential> signInWithApple() async {
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );

    final userCredential = await _auth.signInWithCredential(oauthCredential);

    // Apple only sends the name on the first sign-in; persist it.
    final displayName = [
      appleCredential.givenName,
      appleCredential.familyName,
    ].where((n) => n != null).join(' ');

    if (displayName.isNotEmpty &&
        (userCredential.user?.displayName == null ||
            userCredential.user!.displayName!.isEmpty)) {
      await userCredential.user?.updateDisplayName(displayName);
      await userCredential.user?.reload();
    }

    return userCredential;
  }

  // ── Sign Out ─────────────────────────────────────────────────
  Future<void> signOut() async {
    // Sign out from all providers. If any provider fails, continue with
    // the remaining sign-outs but track the failure so the caller knows
    // the session may not be fully invalidated.
    String? signOutError;

    try {
      await _auth.signOut();
    } catch (e) {
      signOutError = 'Firebase sign-out failed: $e';
      debugPrint('Firebase sign-out failed: $e');
    }

    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // Google sign out failure is non-critical (no persistent session).
    }

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      // Supabase sign-out failure is security-relevant: the Supabase JWT
      // may remain valid for its remaining TTL. Log and propagate.
      signOutError = 'Supabase session may still be active: $e';
      debugPrint('Supabase sign-out failed — JWT may persist: $e');
    }

    if (signOutError != null) {
      throw StateError(
        'Sign-out partially failed. Please close the app and try again.',
      );
    }
  }

  // ── Password Reset ───────────────────────────────────────────
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }
}
