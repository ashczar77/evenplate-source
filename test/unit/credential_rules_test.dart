import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/security/credential_rules.dart';

void main() {
  group('validateEmail', () {
    test('accepts an ordinary address', () {
      expect(CredentialRules.validateEmail('user@evenplate.app'), isNull);
    });

    test('accepts surrounding whitespace', () {
      expect(CredentialRules.validateEmail('  user@evenplate.app  '), isNull);
    });

    test('rejects an empty address', () {
      expect(CredentialRules.validateEmail(''), isNotNull);
      expect(CredentialRules.validateEmail('   '), isNotNull);
    });

    test('rejects an address with no domain dot', () {
      expect(CredentialRules.validateEmail('user@localhost'), isNotNull);
    });

    test('rejects an address with no at sign', () {
      expect(CredentialRules.validateEmail('user.evenplate.app'), isNotNull);
    });

    test('rejects an address with spaces inside', () {
      expect(CredentialRules.validateEmail('us er@evenplate.app'), isNotNull);
    });

    test('accepts plus addressing and subdomains', () {
      expect(
        CredentialRules.validateEmail('user+tag@mail.evenplate.co.uk'),
        isNull,
      );
    });
  });

  group('validateSignIn', () {
    test('accepts any non empty password', () {
      expect(
        CredentialRules.validateSignIn(
          email: 'user@evenplate.app',
          password: 'short',
        ),
        isNull,
      );
    });

    test('rejects an empty password', () {
      expect(
        CredentialRules.validateSignIn(
          email: 'user@evenplate.app',
          password: '',
        ),
        isNotNull,
      );
    });

    // Sign in must not apply the sign up strength rules, or accounts created
    // under an older policy could never log in again.
    test('does not apply the sign up length rule', () {
      expect(
        CredentialRules.validateSignIn(
          email: 'user@evenplate.app',
          password: 'abc123',
        ),
        isNull,
      );
    });

    test('still validates the email', () {
      expect(
        CredentialRules.validateSignIn(email: 'nope', password: 'whatever'),
        isNotNull,
      );
    });
  });

  group('validateSignUp', () {
    test('accepts a mixed case password with a number and a symbol', () {
      expect(
        CredentialRules.validateSignUp(
          email: 'user@evenplate.app',
          password: 'balancedPlate7!',
        ),
        isNull,
      );
    });

    test('rejects a password below the minimum length', () {
      expect(
        CredentialRules.validateSignUp(
          email: 'user@evenplate.app',
          password: 'abc123',
        ),
        contains('${CredentialRules.minPasswordLength} characters'),
      );
    });

    test('rejects a password with no uppercase letter', () {
      expect(
        CredentialRules.validateSignUp(
          email: 'user@evenplate.app',
          password: 'balancedplate7!',
        ),
        contains('uppercase letter'),
      );
    });

    test('rejects a password with no lowercase letter', () {
      expect(
        CredentialRules.validateSignUp(
          email: 'user@evenplate.app',
          password: 'BALANCEDPLATE7!',
        ),
        contains('lowercase letter'),
      );
    });

    test('rejects a password with no digit', () {
      expect(
        CredentialRules.validateSignUp(
          email: 'user@evenplate.app',
          password: 'balancedPlate!',
        ),
        contains('a number'),
      );
    });

    test('rejects a password with no symbol', () {
      expect(
        CredentialRules.validateSignUp(
          email: 'user@evenplate.app',
          password: 'balancedPlate7',
        ),
        contains('a symbol'),
      );
    });

    test('rejects a password equal to the email', () {
      expect(
        CredentialRules.validateSignUp(
          email: 'User1@evenplate.app',
          password: 'User1@evenplate.app',
        ),
        contains('same as your email'),
      );
    });

    test('rejects a password equal to the email in a different case', () {
      expect(
        CredentialRules.validateSignUp(
          email: 'user1@evenplate.app',
          password: 'User1@evenplate.app',
        ),
        contains('same as your email'),
      );
    });

    test('counts a space as a character rather than stripping it', () {
      // The password is not trimmed anywhere, so a leading space is content.
      expect(
        CredentialRules.validateSignUp(
          email: 'user@evenplate.app',
          password: ' Plate123!',
        ),
        isNull,
      );
    });

    test('reports the email problem before the password problem', () {
      expect(
        CredentialRules.validateSignUp(email: '', password: 'x'),
        contains('email'),
      );
    });
  });
}
