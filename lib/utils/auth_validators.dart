class AuthValidators {
  static final RegExp _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  static final RegExp _nameRegex = RegExp(r"^[A-Za-z][A-Za-z '.-]{1,49}$");

  static const Set<String> _blockedEmailDomains = {
    'mailinator.com',
    'tempmail.com',
    '10minutemail.com',
    'guerrillamail.com',
    'yopmail.com',
    'trashmail.com',
    'dispostable.com',
    'fakeinbox.com',
    'throwaway.email',
    'temp-mail.org',
    'sharklasers.com',
    'grr.la',
    'guerrillamailblock.com',
    'tempail.com',
    'maildrop.cc',
    'mohmal.com',
    'getairmail.com',
    'saynotospams.com',
    'meltmail.com',
    'my10minutemail.com',
    'tempmail.net',
    'throwawaymail.com',
    'minuteinbox.com',
    'mailcatch.com',
    'dropmail.me',
    'tempmail.ninja',
    'fakemail.net',
  };

  static String? validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Full name is required';
    if (!_nameRegex.hasMatch(name)) return 'Enter a valid full name';
    return null;
  }

  static String? validateEmail(String? value) {
    final email = (value ?? '').trim().toLowerCase();
    if (email.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(email)) return 'Enter a valid email address';

    final parts = email.split('@');
    if (parts.length != 2) return 'Enter a valid email address';
    if (_blockedEmailDomains.contains(parts[1])) {
      return 'Disposable emails are not allowed';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    final rules = passwordRules(value ?? '');
    if ((value ?? '').isEmpty) return 'Password is required';
    if (!rules.isValid) {
      return 'Password does not meet all requirements';
    }
    return null;
  }

  /// Maximum password length to prevent long-password DoS attacks against
  /// the hashing function. Firebase Auth itself enforces limits, but we
  /// reject early on the client to avoid wasting bandwidth.
  static const int _maxPasswordLength = 128;

  static PasswordRules passwordRules(String password) {
    return PasswordRules(
      minLength: password.length >= 8,
      maxLength: password.length <= _maxPasswordLength,
      hasUppercase: RegExp(r'[A-Z]').hasMatch(password),
      hasLowercase: RegExp(r'[a-z]').hasMatch(password),
      hasNumber: RegExp(r'[0-9]').hasMatch(password),
      hasSpecial: RegExp(r'[^A-Za-z0-9]').hasMatch(password),
    );
  }

  static String? validateConfirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return 'Confirm your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }

  /// Validates phone number format: digits only, 4-15 characters (E.164 body).
  /// The country code prefix is added separately, so this validates the
  /// national number portion only.
  static String? validatePhoneNumber(String? value) {
    final phone = (value ?? '').trim();
    if (phone.isEmpty) return 'Phone number is required';
    if (!RegExp(r'^\d{4,15}$').hasMatch(phone)) {
      return 'Enter a valid phone number (digits only)';
    }
    return null;
  }
}

class PasswordRules {
  const PasswordRules({
    required this.minLength,
    required this.maxLength,
    required this.hasUppercase,
    required this.hasLowercase,
    required this.hasNumber,
    required this.hasSpecial,
  });

  final bool minLength;
  final bool maxLength;
  final bool hasUppercase;
  final bool hasLowercase;
  final bool hasNumber;
  final bool hasSpecial;

  bool get isValid =>
      minLength &&
      maxLength &&
      hasUppercase &&
      hasLowercase &&
      hasNumber &&
      hasSpecial;
}
