import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../ui_components.dart';
import '../utils/auth_validators.dart';

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});
  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _authService = AuthService();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _codeSent = false;
  String? _verificationId;
  DateTime? _lastOtpSentAt;

  Country _selectedCountry = Country(
    phoneCode: "91",
    countryCode: "IN",
    e164Sc: 0,
    geographic: true,
    level: 1,
    name: "India",
    example: "India",
    displayName: "India",
    displayNameNoCountryCode: "IN",
    e164Key: "",
  );

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  Future<void> _sendOTP() async {
    if (_phoneController.text.isEmpty) return;
    // Validate phone number format before sending
    final phoneError =
        AuthValidators.validatePhoneNumber(_phoneController.text.trim());
    if (phoneError != null) {
      _showError(phoneError);
      return;
    }
    // Rate limit: 60 seconds between OTP requests
    final now = DateTime.now();
    if (_lastOtpSentAt != null &&
        now.difference(_lastOtpSentAt!).inSeconds < 60) {
      final remaining = 60 - now.difference(_lastOtpSentAt!).inSeconds;
      _showError('Please wait $remaining seconds before requesting another code.');
      return;
    }
    _lastOtpSentAt = now;
    setState(() => _isLoading = true);
    try {
      await _authService.signInWithPhone(
        phoneNumber:
            '+${_selectedCountry.phoneCode}${_phoneController.text.trim()}',
        onCodeSent: (verificationId, resendToken) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _codeSent = true;
              _isLoading = false;
            });
          }
        },
        onAutoVerified: (credential) async {
          try {
            await _authService.signInWithCredential(credential);
            if (mounted) {
              Navigator.popUntil(context, (route) => route.isFirst);
            }
          } catch (_) {}
        },
        onError: (e) {
          if (mounted) {
            setState(() => _isLoading = false);
            _showError('Failed to send code.');
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(
            'Could not send code. Please check your internet connection.');
      }
    }
  }

  Future<void> _verifyOTP() async {
    if (_codeController.text.length != 6) return;
    setState(() => _isLoading = true);
    try {
      await _authService.verifyOTP(
          verificationId: _verificationId!, smsCode: _codeController.text);
      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } catch (e) {
      _showError('Invalid verification code.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, 
              color: isDark ? Colors.white : Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Text(
                _codeSent ? 'Enter Code' : 'Phone Login',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _codeSent
                    ? 'We sent a 6-digit code to your phone.'
                    : 'Enter your phone number to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 40),
              if (!_codeSent) ...[
                buildRoundedTextField(
                  context: context,
                  controller: _phoneController,
                  hint: 'Phone Number',
                  isDark: isDark,
                  keyboardType: TextInputType.phone,
                  prefixIcon: InkWell(
                    onTap: () {
                      showCountryPicker(
                        context: context,
                        showPhoneCode: true,
                        countryListTheme: CountryListThemeData(
                          backgroundColor: theme.colorScheme.surface,
                          bottomSheetHeight: 500,
                          textStyle: TextStyle(color: theme.colorScheme.onSurface),
                          searchTextStyle: TextStyle(color: theme.colorScheme.onSurface),
                          inputDecoration: InputDecoration(
                            labelText: 'Search',
                            hintText: 'Start typing to search',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        onSelect: (Country country) {
                          setState(() {
                            _selectedCountry = country;
                          });
                        },
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_selectedCountry.flagEmoji} +${_selectedCountry.phoneCode}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                buildPrimaryButton(
                  context: context,
                  label: 'Send Code',
                  isLoading: _isLoading,
                  onPressed: _isLoading ? null : _sendOTP,
                ),
              ] else ...[
                buildRoundedTextField(
                  context: context,
                  controller: _codeController,
                  hint: 'Verification Code',
                  icon: Icons.security_outlined,
                  isDark: isDark,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 32),
                buildPrimaryButton(
                  context: context,
                  label: 'Verify',
                  isLoading: _isLoading,
                  onPressed: _isLoading ? null : _verifyOTP,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() => _codeSent = false),
                  child: Text(
                    'Change Number',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
