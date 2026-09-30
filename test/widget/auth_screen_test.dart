import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenplate/core/security/auth_user_messages.dart';
import 'package:evenplate/core/security/credential_rules.dart';
import 'package:evenplate/core/theme/even_colors.dart';
import 'package:evenplate/core/theme/even_theme.dart';
import 'package:evenplate/features/auth/auth_screen.dart';
import 'package:evenplate/services/local_storage_service.dart';
import 'package:evenplate/services/supabase_service.dart';

void main() {
  late LocalStorageService storage;
  late SupabaseService supabase;

  setUp(() {
    storage = LocalStorageService();
    supabase = SupabaseService(storage);
  });

  Widget createAuthWidget({
    VoidCallback? onAuthSuccess,
    ThemeMode themeMode = ThemeMode.dark,
  }) {
    return MaterialApp(
      theme: EvenTheme.lightTheme,
      darkTheme: EvenTheme.darkTheme,
      themeMode: themeMode,
      home: AuthScreen(
        supabase: supabase,
        storage: storage,
        onAuthSuccess: onAuthSuccess ?? () {},
      ),
    );
  }

  testWidgets('AuthScreen renders brand header, tabs, and email sign-in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createAuthWidget());
    await tester.pump();

    expect(find.text('EvenPlate', findRichText: true), findsOneWidget);
    expect(find.text('Sign In'), findsWidgets);
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.byKey(const ValueKey('input_email')), findsOneWidget);
    expect(find.byKey(const ValueKey('input_password')), findsOneWidget);
    expect(find.byKey(const ValueKey('btn_primary_auth')), findsOneWidget);
    expect(find.byKey(const ValueKey('btn_guest_sign_in')), findsNothing);
    expect(find.textContaining('Continue as Guest'), findsNothing);
    expect(find.byKey(const ValueKey('link_privacy')), findsOneWidget);
    expect(find.byKey(const ValueKey('link_terms')), findsOneWidget);
    expect(find.byKey(const ValueKey('forgot_password')), findsOneWidget);
    expect(find.byKey(const ValueKey('resend_confirmation')), findsNothing);
  });

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('btn_primary_auth')));
    await tester.pump();
  }

  Future<void> fill(
    WidgetTester tester, {
    String? email,
    String? password,
  }) async {
    if (email != null) {
      await tester.enterText(find.byKey(const ValueKey('input_email')), email);
    }
    if (password != null) {
      await tester.enterText(
        find.byKey(const ValueKey('input_password')),
        password,
      );
    }
  }

  testWidgets('AuthScreen validates the email address', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createAuthWidget());
    await tester.pump();

    await submit(tester);
    expect(find.text('Please enter your email address.'), findsOneWidget);

    await fill(tester, email: 'invalid-email');
    await submit(tester);
    expect(find.text('Please enter a valid email address.'), findsOneWidget);
    expect(find.byKey(const ValueKey('banner_auth_error')), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.error_outline_rounded)).color,
      EvenColors.crashWarning,
    );

    await fill(tester, email: 'user@localhost');
    await submit(tester);
    expect(find.text('Please enter a valid email address.'), findsOneWidget);
  });

  testWidgets('Sign in requires a password but does not judge its strength', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createAuthWidget());
    await tester.pump();

    await fill(tester, email: 'user@evenplate.app', password: '');
    await submit(tester);
    expect(find.text('Please enter your password.'), findsOneWidget);

    // A short password is accepted on sign in. Applying the sign up rule here
    // would lock out any account created under an older policy.
    await fill(tester, password: 'abc123');
    await submit(tester);
    expect(find.textContaining('at least'), findsNothing);
  });

  testWidgets(
    'auth mode changes clear and mask the password but preserve email',
    (tester) async {
      await tester.pumpWidget(createAuthWidget());
      await fill(
        tester,
        email: 'user@evenplate.app',
        password: 'balancedPlate7!',
      );
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('input_password')))
            .obscureText,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('tab_sign_up')));
      await tester.pump();
      final password = tester.widget<TextField>(
        find.byKey(const ValueKey('input_password')),
      );
      expect(password.controller!.text, isEmpty);
      expect(password.obscureText, isTrue);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('input_email')))
            .controller!
            .text,
        'user@evenplate.app',
      );
      await fill(tester, password: 'balancedPlate7!');
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.tap(find.byKey(const ValueKey('tab_sign_in')));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('input_password')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('input_password')))
            .obscureText,
        isTrue,
      );
    },
  );

  testWidgets('rejected sign-in clears and masks the password', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          supabase: _RejectedSignInSupabase(storage),
          storage: storage,
          onAuthSuccess: () {},
        ),
      ),
    );
    await fill(
      tester,
      email: 'user@evenplate.app',
      password: 'balancedPlate7!',
    );
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('banner_auth_error')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('input_password')))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('input_password')))
          .obscureText,
      isTrue,
    );
  });

  testWidgets('Sign up enforces password strength', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createAuthWidget());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('tab_sign_up')));
    await tester.pump();

    await fill(tester, email: 'user@evenplate.app', password: 'abc123');
    await submit(tester);
    expect(
      find.text('Password must be at least 10 characters.'),
      findsOneWidget,
    );

    await fill(tester, password: 'balancedplate7!');
    await submit(tester);
    expect(
      find.text('Password must include an uppercase letter.'),
      findsOneWidget,
    );

    await fill(tester, password: 'balancedPlate7');
    await submit(tester);
    expect(find.text('Password must include a symbol.'), findsOneWidget);

    await fill(tester, password: 'balancedPlate7!');
    await submit(tester);
    expect(find.textContaining('Password must'), findsNothing);
  });

  testWidgets('Signing in with email triggers onAuthSuccess callback', (
    WidgetTester tester,
  ) async {
    bool authSuccessCalled = false;

    await tester.pumpWidget(
      createAuthWidget(
        onAuthSuccess: () {
          authSuccessCalled = true;
        },
      ),
    );
    await tester.pump();

    await fill(tester, email: 'user@evenplate.app', password: 'balancedPlate7');
    await submit(tester);
    await tester.pumpAndSettle();

    expect(authSuccessCalled, isTrue);
  });

  testWidgets('Privacy Policy link opens the privacy document', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createAuthWidget());
    await tester.pump();

    final privacy = find.byKey(const ValueKey('link_privacy'));
    await tester.ensureVisible(privacy);
    await tester.tap(privacy);
    await tester.pumpAndSettle();

    expect(find.text('Privacy Policy'), findsWidgets);
    expect(find.textContaining('What we collect'), findsOneWidget);
  });

  testWidgets('Switching between Sign In and Create Account updates UI', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createAuthWidget());
    await tester.pump();

    // Switch to Create Account
    await tester.tap(find.byKey(const ValueKey('tab_sign_up')));
    await tester.pump();

    expect(
      find.widgetWithText(ElevatedButton, 'Create Account'),
      findsOneWidget,
    );
    expect(find.text(CredentialRules.signUpHint), findsOneWidget);
    expect(find.byKey(const ValueKey('forgot_password')), findsNothing);
    expect(find.byKey(const ValueKey('resend_confirmation')), findsNothing);

    // Switch back to Sign In
    await tester.tap(find.byKey(const ValueKey('tab_sign_in')));
    await tester.pump();

    expect(find.widgetWithText(ElevatedButton, 'Sign In'), findsOneWidget);
  });

  testWidgets(
    'Create Account without a session asks to confirm email and does not resend',
    (WidgetTester tester) async {
      final confirming = _ConfirmEmailSupabase(storage);
      await tester.pumpWidget(
        MaterialApp(
          theme: EvenTheme.lightTheme,
          darkTheme: EvenTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: AuthScreen(
            supabase: confirming,
            storage: storage,
            onAuthSuccess: () {},
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('tab_sign_up')));
      await tester.pump();
      await fill(
        tester,
        email: 'user@evenplate.app',
        password: 'balancedPlate7!',
      );
      await submit(tester);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('input_password')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('input_password')))
            .obscureText,
        isTrue,
      );
      expect(confirming.signUpCalls, 1);
      expect(find.text(AuthUserMessages.confirmEmailSent), findsOneWidget);
      expect(find.byKey(const ValueKey('banner_auth_notice')), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Sign In'), findsOneWidget);
      expect(find.byKey(const ValueKey('resend_confirmation')), findsOneWidget);

      await fill(tester, email: 'different@evenplate.app');
      await tester.pump();
      expect(find.byKey(const ValueKey('resend_confirmation')), findsNothing);
      await fill(tester, email: 'user@evenplate.app');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('tab_sign_up')));
      await tester.pump();
      await fill(tester, password: 'balancedPlate7!');
      await submit(tester);
      await tester.pumpAndSettle();

      expect(confirming.signUpCalls, 1);
      expect(find.text(AuthUserMessages.confirmEmailSent), findsOneWidget);
    },
  );

  testWidgets('Create Account for an existing email switches to Sign In', (
    WidgetTester tester,
  ) async {
    final existing = _ExistingAccountSupabase(storage);
    await tester.pumpWidget(
      MaterialApp(
        theme: EvenTheme.lightTheme,
        darkTheme: EvenTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: AuthScreen(
          supabase: existing,
          storage: storage,
          onAuthSuccess: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('tab_sign_up')));
    await tester.pump();
    await fill(
      tester,
      email: 'user@evenplate.app',
      password: 'balancedPlate7!',
    );
    await submit(tester);
    await tester.pumpAndSettle();

    expect(find.text(AuthUserMessages.accountExists), findsOneWidget);
    expect(find.byKey(const ValueKey('banner_auth_error')), findsOneWidget);
    expect(find.byKey(const ValueKey('banner_auth_notice')), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Sign In'), findsOneWidget);
  });
}

class _ConfirmEmailSupabase extends SupabaseService {
  _ConfirmEmailSupabase(super.storage);

  int signUpCalls = 0;

  @override
  Future<EmailAuthOutcome> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    signUpCalls += 1;
    return EmailAuthOutcome.confirmEmail;
  }
}

class _ExistingAccountSupabase extends SupabaseService {
  _ExistingAccountSupabase(super.storage);

  @override
  Future<EmailAuthOutcome> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    return EmailAuthOutcome.accountExists;
  }
}

class _RejectedSignInSupabase extends SupabaseService {
  _RejectedSignInSupabase(super.storage);
  @override
  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async => false;
}
