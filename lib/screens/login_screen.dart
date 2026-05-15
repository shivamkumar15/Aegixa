import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../ui_components.dart';
import '../utils/auth_validators.dart';
import 'phone_auth_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _loadingProvider;
  DateTime? _lastPasswordResetAt;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _loadingProvider = 'email';
    });
    try {
      await _authService.signInWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text);
      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-not-verified') {
        // Use generic message to prevent email enumeration — don't reveal
        // that the account exists but is unverified.
        _showError('Invalid email or password.');
      } else {
        _showError('Invalid email or password.');
      }
    } catch (e) {
      _showError('Invalid email or password.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingProvider = null;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _loadingProvider = 'google';
    });
    try {
      await _authService.signInWithGoogle();
      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } catch (e) {
      if (!e.toString().contains('cancelled')) {
        _showError('Google sign-in failed.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingProvider = null;
        });
      }
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _isLoading = true;
      _loadingProvider = 'apple';
    });
    try {
      await _authService.signInWithApple();
      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } catch (e) {
      _showError('Apple sign-in failed.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingProvider = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isIOS = !kIsWeb && Platform.isIOS;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF000000) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 8),
                  Hero(
                    tag: 'app_logo',
                    child: Image.asset(
                      'assets/Logo.png',
                      width: 200,
                      height: 180,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Welcome back',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Login to your account',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white70 : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 40),

                  buildRoundedTextField(
                    context: context,
                    controller: _emailController,
                    hint: 'Email address',
                    icon: Icons.email_outlined,
                    isDark: isDark,
                    validator: AuthValidators.validateEmail,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 20),

                  buildRoundedTextField(
                    context: context,
                    controller: _passwordController,
                    hint: 'Password',
                    icon: Icons.lock_outline,
                    isDark: isDark,
                    obscure: _obscurePassword,
                    validator: (v) =>
                        (v ?? '').isEmpty ? 'Password is required' : null,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: isDark ? Colors.white54 : Colors.grey[400],
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),


                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _handleForgotPassword,
                      child: Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),


                  buildPrimaryButton(
                    context: context,
                    label: 'Login',
                    onPressed: _isLoading ? null : _signInWithEmail,
                    isLoading: _loadingProvider == 'email',
                  ),

                  const SizedBox(height: 40),

                  Row(
                    children: [
                      Expanded(
                          child: Divider(
                              color:
                                  isDark ? Colors.white10 : Colors.grey[300])),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Or Login with',
                          style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.grey[500],
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                          child: Divider(
                              color:
                                  isDark ? Colors.white10 : Colors.grey[300])),
                    ],
                  ),

                  const SizedBox(height: 30),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      buildSocialIcon(
                        context: context,
                        icon: Icons.phone_android_rounded,
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const PhoneAuthScreen()),
                                ),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 20),
                      buildSocialIcon(
                        context: context,
                        icon: Icons.g_mobiledata_rounded,
                        size: 40,
                        onPressed: _isLoading ? null : _signInWithGoogle,
                        isDark: isDark,
                        isLoading: _loadingProvider == 'google',
                      ),
                      if (isIOS) ...[
                        const SizedBox(width: 20),
                        buildSocialIcon(
                          context: context,
                          icon: Icons.apple_rounded,
                          onPressed: _isLoading ? null : _signInWithApple,
                          isDark: isDark,
                          isLoading: _loadingProvider == 'apple',
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 40),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have account? ",
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey[600],
                          fontSize: 15,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SignUpScreen()),
                        ),
                        child: Text(
                          'Sign up',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('Enter your email first');
      return;
    }
    final emailError = AuthValidators.validateEmail(email);
    if (emailError != null) {
      _showError(emailError);
      return;
    }
    final now = DateTime.now();
    if (_lastPasswordResetAt != null &&
        now.difference(_lastPasswordResetAt!).inSeconds < 60) {
      final remaining = 60 - now.difference(_lastPasswordResetAt!).inSeconds;
      _showError(
          'Please wait $remaining seconds before requesting another reset.');
      return;
    }
    _lastPasswordResetAt = now;
    try {
      await _authService.sendPasswordResetEmail(email);
    } catch (_) {
      // Silently ignore — we show the same generic message regardless so as
      // not to reveal whether the email exists.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('If that email is registered, a reset link has been sent.')));
  }
}
