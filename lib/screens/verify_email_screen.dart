import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _authService = AuthService();
  bool _sending = false;
  bool _refreshing = false;

  void _showMessage(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  Future<void> _resendEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _sending = true);
    try {
      await _authService.sendVerificationEmailWithRateLimit(user);
      _showMessage('Verification link sent. Check inbox/spam.');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'verification-email-rate-limited') {
        _showMessage(e.message ?? 'Please wait before requesting again.',
            isError: true);
      } else {
        _showMessage(e.message ?? 'Could not send verification email.',
            isError: true);
      }
    } catch (_) {
      _showMessage('Could not send verification email.', isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _checkVerification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _refreshing = true);
    try {
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      if ((refreshed?.emailVerified ?? false) && mounted) {
        _showMessage('Email verified. Welcome!');
      } else {
        _showMessage('Email not verified yet. Please check your mail.',
            isError: true);
      }
    } catch (_) {
      _showMessage(
          'Could not check verification status. Please check your internet connection.',
          isError: true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;
    final isBusy = _sending || _refreshing;
    final remainingSeconds =
        _authService.verificationEmailCooldownRemainingSeconds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify email'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.mark_email_unread_outlined,
                      size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Please verify your email first to login to the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((user?.email ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      user!.email!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed:
                        (isBusy || remainingSeconds > 0) ? null : _resendEmail,
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Resend verification link'),
                  ),
                  if (remainingSeconds > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      'You can request a new link in $remainingSeconds seconds.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: isBusy ? null : _checkVerification,
                    child: _refreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('I have verified'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: isBusy ? null : _authService.signOut,
                    child: const Text('Use another account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
