/// Maps backend auth failures to copy the user can act on.
class AuthUserMessages {
  AuthUserMessages._();

  static const wrongCredentials =
      'That email or password is not right. Try again.';
  static const genericFailure =
      'Something went wrong. Check your details and try again.';
  static const confirmEmailSent =
      'Check your inbox and confirm your email, then sign in.';
  static const emailNotConfirmed = 'Confirm your email, then try signing in.';
  static const emailSendPaused =
      'The confirmation mailer is temporarily full. Sign in if this account already exists, or try again later.';
  static const tooManyAttempts =
      'That request was throttled. Wait a minute and try again.';
  static const accountExists =
      'An account with that email already exists. Sign in instead.';

  static String fromAuthFailure({String? code, String? message}) {
    final haystack = '${code ?? ''} ${message ?? ''}'.toLowerCase();

    if (_hasAny(haystack, const [
      'invalid_credentials',
      'invalid login credentials',
    ])) {
      return wrongCredentials;
    }
    if (_hasAny(haystack, const [
      'email_not_confirmed',
      'email not confirmed',
    ])) {
      return emailNotConfirmed;
    }
    if (_hasAny(haystack, const [
      'user_already_exists',
      'email_exists',
      'already registered',
    ])) {
      return accountExists;
    }
    if (haystack.contains('weak_password')) {
      return 'Choose a stronger password.';
    }
    if (_hasAny(haystack, const [
      'over_email_send_rate_limit',
      'email rate limit',
    ])) {
      return emailSendPaused;
    }
    if (_hasAny(haystack, const [
      'over_request_rate_limit',
      'too many requests',
    ])) {
      return tooManyAttempts;
    }
    if (_hasAny(haystack, const ['user_banned', 'user_disabled'])) {
      return 'This account cannot sign in.';
    }
    if (haystack.contains('signup_disabled')) {
      return 'New accounts are not available right now.';
    }
    return genericFailure;
  }

  static bool _hasAny(String haystack, List<String> needles) {
    return needles.any(haystack.contains);
  }
}
