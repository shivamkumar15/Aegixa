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
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_codeSent ? 'Enter Code' : 'What is your number?',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                      letterSpacing: -1)),
              const SizedBox(height: 8),
              Text(
                  _codeSent
                      ? 'We sent a 6-digit code to your phone.'
                      : 'We will send a verification code to this number.',
                  style: TextStyle(
                      fontSize: 16,
                      color: isDark
                          ? const Color(0xFFA3A3A3)
                          : const Color(0xFF6B7280))),
              const SizedBox(height: 40),
              if (!_codeSent) ...[
                buildTextField(
                  context: context,
                  label: 'Phone Number',
                  hint: '',
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  prefixIcon: InkWell(
                    onTap: () {
                      showCountryPicker(
                        context: context,
                        showPhoneCode: true,
                        countryListTheme: CountryListThemeData(
                          backgroundColor: theme.colorScheme.surface,
                          bottomSheetHeight: 500,
                          textStyle:
                              TextStyle(color: theme.colorScheme.onSurface),
                          searchTextStyle:
                              TextStyle(color: theme.colorScheme.onSurface),
                          inputDecoration: InputDecoration(
                            labelText: 'Search',
                            hintText: 'Start typing to search',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark
                                    ? const Color(0xFF2A2A2A)
                                    : const Color(0xFFE5E7EB),
                              ),
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
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_drop_down,
                              color: theme.colorScheme.onSurface),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                buildButton(
                  context: context,
                  label: 'Send Code',
                  isLoading: _isLoading,
                  onPressed: _isLoading ? null : _sendOTP,
                ),
              ] else ...[
                buildTextField(
                  context: context,
                  label: 'Verification Code',
                  hint: '123456',
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 32),
                buildButton(
                  context: context,
                  label: 'Verify',
                  isLoading: _isLoading,
                  onPressed: _isLoading ? null : _verifyOTP,
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _codeSent = false),
                    child: Text('Change Number',
                        style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold)),
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
