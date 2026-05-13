import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../ui_components.dart';
import '../utils/auth_validators.dart';
import 'login_screen.dart';
import 'phone_auth_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _loadingProvider;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _signUpWithEmail() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final passwordError =
        AuthValidators.validatePassword(_passwordController.text);
    if (passwordError != null) {
      _showError(passwordError);
      return;
    }

    final confirmError = AuthValidators.validateConfirmPassword(
      _confirmPasswordController.text,
      _passwordController.text,
    );
    if (confirmError != null) {
      _showError(confirmError);
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingProvider = 'email';
    });

    try {
      await _authService.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _emailController.text.trim().split('@').first,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Account created. Verify your email, then sign in to continue.',
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        // Use generic message to prevent email enumeration — don't confirm
        // whether the email is registered or not.
        _showError('Could not create account. Try logging in instead.');
      } else if (e.code == 'weak-password') {
        _showError('Use a stronger password to continue.');
      } else if (e.code == 'too-many-requests') {
        _showError('Too many attempts. Please wait a bit and try again.');
      } else {
        _showError(e.message ?? 'Could not create account right now.');
      }
    } catch (_) {
      _showError('Could not create account right now.');
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
    } catch (_) {
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
    final passwordRules =
        AuthValidators.passwordRules(_passwordController.text);

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
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 0),
                  // Logo
                  Hero(
                    tag: 'app_logo',
                    child: Image.asset(
                      'assets/Logo.png',
                      width: 200,
                      height: 200,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Title
                  Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Email Field
                  buildRoundedTextField(
                    context: context,
                    controller: _emailController,
                    hint: 'Email address',
                    icon: Icons.email_outlined,
                    isDark: isDark,
                    validator: AuthValidators.validateEmail,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),

                  // Password Field
                  buildRoundedTextField(
                    context: context,
                    controller: _passwordController,
                    hint: 'Password',
                    icon: Icons.lock_outline,
                    isDark: isDark,
                    obscure: _obscurePassword,
                    validator: (value) =>
                        (value ?? '').isEmpty ? 'Password is required' : null,
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
                  const SizedBox(height: 12),

                  // Confirm Password Field
                  buildRoundedTextField(
                    context: context,
                    controller: _confirmPasswordController,
                    hint: 'Confirm password',
                    icon: Icons.lock_outline,
                    isDark: isDark,
                    obscure: _obscureConfirmPassword,
                    validator: (value) => (value ?? '').isEmpty
                        ? 'Confirm password is required'
                        : null,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: isDark ? Colors.white54 : Colors.grey[400],
                        size: 20,
                      ),
                      onPressed: () => setState(() =>
                          _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Password Rules
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _PasswordRuleChip(
                            label: '8+ chars', isMet: passwordRules.minLength),
                        _PasswordRuleChip(
                            label: 'Number', isMet: passwordRules.hasNumber),
                        _PasswordRuleChip(
                            label: 'Special', isMet: passwordRules.hasSpecial),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Sign Up Button
                  buildPrimaryButton(
                    context: context,
                    label: 'Sign Up',
                    onPressed: _isLoading ? null : _signUpWithEmail,
                    isLoading: _loadingProvider == 'email',
                  ),

                  const SizedBox(height: 20),

                  // Or login with
                  Row(
                    children: [
                      Expanded(
                          child: Divider(
                              color:
                                  isDark ? Colors.white10 : Colors.grey[300])),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Or Sign up with',
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

                  const SizedBox(height: 16),

                  // Social Buttons Row
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

                  const SizedBox(height: 15),

                  // Log in link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Already have an account? ",
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey[600],
                          fontSize: 15,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Text(
                          'Log in',
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
}

class _PasswordRuleChip extends StatelessWidget {
  const _PasswordRuleChip({required this.label, required this.isMet});

  final String label;
  final bool isMet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMet
            ? theme.colorScheme.primary
            : (isDark ? const Color(0xFF171717) : const Color(0xFFF3F4F6)),
        borderRadius: BorderRadius.circular(999),
        boxShadow: isMet
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMet ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 14,
            color: isMet
                ? Colors.black
                : (isDark ? const Color(0xFFA3A3A3) : const Color(0xFF6B7280)),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isMet
                  ? Colors.black
                  : (isDark ? const Color(0xFFD1D5DB) : const Color(0xFF4B5563)),
            ),
          ),
        ],
      ),
    );
  }
}
