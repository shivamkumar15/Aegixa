import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../ui_components.dart';
import '../utils/auth_validators.dart';
import 'phone_auth_screen.dart';

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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/Logo.png',
                        width: 120,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: Text('Welcome back',
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                              letterSpacing: -1)),
                    ),
                    const SizedBox(height: 6),
                    const SizedBox(height: 28),
                    buildTextField(
                      context: context,
                      label: 'Email address',
                      hint: '',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      validator: AuthValidators.validateEmail,
                    ),
                    const SizedBox(height: 16),
                    buildTextField(
                      context: context,
                      label: 'Password',
                      hint: '••••••••',
                      controller: _passwordController,
                      obscure: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: isDark
                                ? const Color(0xFFB3B3B3)
                                : const Color(0xFF9CA3AF)),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      validator: (v) {
                        if ((v ?? '').isEmpty) {
                          return 'Password is required';
                        }
                        return null;
                      },
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          final email = _emailController.text.trim();
                          if (email.isEmpty) {
                            _showError('Enter your email first');
                            return;
                          }
                          // Validate email format before sending
                          final emailError = AuthValidators.validateEmail(email);
                          if (emailError != null) {
                            _showError(emailError);
                            return;
                          }
                          // Rate limit: 60 seconds between reset requests
                          final now = DateTime.now();
                          if (_lastPasswordResetAt != null &&
                              now.difference(_lastPasswordResetAt!).inSeconds < 60) {
                            final remaining = 60 - now.difference(_lastPasswordResetAt!).inSeconds;
                            _showError('Please wait $remaining seconds before requesting another reset.');
                            return;
                          }
                          _lastPasswordResetAt = now;
                          _authService.sendPasswordResetEmail(email);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('If that email is registered, a reset link has been sent.')));
                        },
                        child: const Text('Forgot password?',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    buildButton(
                      context: context,
                      label: 'Sign in',
                      isLoading: _loadingProvider == 'email',
                      onPressed: _isLoading ? null : _signInWithEmail,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                            child: Divider(
                                color: isDark
                                    ? const Color(0xFF2A2A2A)
                                    : const Color(0xFFE5E7EB))),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('OR',
                              style: TextStyle(
                                  color: Color(0xFFA3A3A3),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                            child: Divider(
                                color: isDark
                                    ? const Color(0xFF2A2A2A)
                                    : const Color(0xFFE5E7EB))),
                      ],
                    ),
                    const SizedBox(height: 18),
                    buildButton(
                      context: context,
                      label: 'Continue with Phone',
                      isOutlined: true,
                      icon: Icon(Icons.phone_android,
                          color: theme.colorScheme.onSurface, size: 20),
                      isLoading: false,
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const PhoneAuthScreen())),
                    ),
                    const SizedBox(height: 10),
                    buildButton(
                      context: context,
                      label: 'Continue with Google',
                      isOutlined: true,
                      isLoading: _loadingProvider == 'google',
                      onPressed: _isLoading ? null : _signInWithGoogle,
                    ),
                    if (isIOS) ...[
                      const SizedBox(height: 10),
                      buildButton(
                        context: context,
                        label: 'Continue with Apple',
                        isOutlined: true,
                        icon: Icon(Icons.apple,
                            color: theme.colorScheme.onSurface, size: 22),
                        isLoading: _loadingProvider == 'apple',
                        onPressed: _isLoading ? null : _signInWithApple,
                      ),
                    ],
                    const SizedBox(height: 22),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
