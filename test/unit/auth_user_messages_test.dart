import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/security/auth_user_messages.dart';

void main() {
  group('AuthUserMessages.fromAuthFailure', () {
    test('maps invalid credentials to a short retry line', () {
      expect(
        AuthUserMessages.fromAuthFailure(code: 'invalid_credentials'),
        AuthUserMessages.wrongCredentials,
      );
      expect(
        AuthUserMessages.fromAuthFailure(
          message:
              'AuthApiException(message: Invalid login credentials, statusCode: 400, code: invalid_credentials)',
        ),
        AuthUserMessages.wrongCredentials,
      );
    });

    test('maps other known codes without leaking the exception', () {
      expect(
        AuthUserMessages.fromAuthFailure(code: 'email_not_confirmed'),
        contains('Confirm your email'),
      );
      expect(
        AuthUserMessages.fromAuthFailure(code: 'email_exists'),
        AuthUserMessages.accountExists,
      );
      expect(
        AuthUserMessages.fromAuthFailure(code: 'over_request_rate_limit'),
        AuthUserMessages.tooManyAttempts,
      );
      expect(
        AuthUserMessages.fromAuthFailure(message: 'Too many requests'),
        AuthUserMessages.tooManyAttempts,
      );
      expect(
        AuthUserMessages.fromAuthFailure(code: 'over_email_send_rate_limit'),
        AuthUserMessages.emailSendPaused,
      );
    });

    test('never returns a raw exception string', () {
      final message = AuthUserMessages.fromAuthFailure(
        message: 'AuthApiException(message: boom, statusCode: 500)',
      );
      expect(message, AuthUserMessages.genericFailure);
      expect(message, isNot(contains('AuthApiException')));
    });
  });
}
