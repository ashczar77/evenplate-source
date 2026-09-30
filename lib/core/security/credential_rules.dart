/// Client side credential checks.
///
/// Supabase is authoritative. These exist to give immediate feedback and to keep
/// obviously weak passwords out of sign up.
class CredentialRules {
  CredentialRules._();

  static const int minPasswordLength = 10;
  static const String signUpHint =
      '10+ characters, with upper and lowercase, a number, and a symbol.';

  static final RegExp _hasUpper = RegExp(r'[A-Z]');
  static final RegExp _hasLower = RegExp(r'[a-z]');
  static final RegExp _hasDigit = RegExp(r'\d');
  static final RegExp _hasSymbol = RegExp(r'[^A-Za-z0-9]');

  /// Deliberately permissive. An aggressive pattern rejects valid addresses,
  /// and the server validates properly anyway.
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? validateEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return 'Please enter your email address.';
    if (!_emailPattern.hasMatch(trimmed)) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  /// Sign in checks presence only. A stricter rule here would lock out accounts
  /// created under an older policy, because the request never reaches Supabase.
  static String? validateSignIn({
    required String email,
    required String password,
  }) {
    final emailError = validateEmail(email);
    if (emailError != null) return emailError;
    if (password.isEmpty) return 'Please enter your password.';
    return null;
  }

  static String? validateSignUp({
    required String email,
    required String password,
  }) {
    final emailError = validateEmail(email);
    if (emailError != null) return emailError;
    if (password.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters.';
    }
    if (!_hasUpper.hasMatch(password)) {
      return 'Password must include an uppercase letter.';
    }
    if (!_hasLower.hasMatch(password)) {
      return 'Password must include a lowercase letter.';
    }
    if (!_hasDigit.hasMatch(password)) {
      return 'Password must include a number.';
    }
    if (!_hasSymbol.hasMatch(password)) {
      return 'Password must include a symbol.';
    }
    if (password.toLowerCase() == email.trim().toLowerCase()) {
      return 'Password cannot be the same as your email address.';
    }
    return null;
  }
}
