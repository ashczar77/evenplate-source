import 'package:flutter/material.dart';
import '../../core/legal/legal_document_screen.dart';
import '../../core/security/auth_user_messages.dart';
import '../../core/security/credential_rules.dart';
import '../../core/theme/even_colors.dart';
import '../../core/utils/sensory_feedback.dart';
import '../../services/local_storage_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/even_brand_lockup.dart';
import '../../widgets/even_notice.dart';
import '../../widgets/glass_card.dart';

/// Email sign-in and create-account. A session requires a real user.
class AuthScreen extends StatefulWidget {
  final SupabaseService supabase;
  final LocalStorageService storage;
  final VoidCallback onAuthSuccess;

  const AuthScreen({
    super.key,
    required this.supabase,
    required this.storage,
    required this.onAuthSuccess,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _submitLocked = false;
  String? _localError;
  String? _localNotice;
  String? _pendingConfirmEmail;
  DateTime? _lastRecoveryEmail;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearPassword() {
    _passwordController.clear();
    _obscurePassword = true;
  }

  void _switchAuthMode(bool signUp) {
    if (_submitLocked || widget.supabase.isLoading || _isSignUp == signUp) {
      return;
    }
    setState(() {
      _isSignUp = signUp;
      _clearPassword();
    });
  }

  Future<void> _handleEmailAuth() async {
    if (_submitLocked) return;

    final email = _emailController.text.trim();
    // Not trimmed: trimming silently changes the password the user chose.
    final password = _passwordController.text;

    final error = _isSignUp
        ? CredentialRules.validateSignUp(email: email, password: password)
        : CredentialRules.validateSignIn(email: email, password: password);
    if (error != null) {
      setState(() {
        _localError = error;
        _localNotice = null;
      });
      return;
    }

    if (_isSignUp && _pendingConfirmEmail == email) {
      setState(() {
        _localError = null;
        _localNotice = AuthUserMessages.confirmEmailSent;
        _isSignUp = false;
        _clearPassword();
      });
      return;
    }

    setState(() {
      _localError = null;
      _localNotice = null;
      _submitLocked = true;
    });
    SensoryFeedback.gentleTap();

    try {
      if (_isSignUp) {
        final outcome = await widget.supabase.signUpWithEmail(
          email: email,
          password: password,
        );
        if (!mounted) return;
        switch (outcome) {
          case EmailAuthOutcome.authenticated:
            SensoryFeedback.zenBloomPulse();
            widget.onAuthSuccess();
          case EmailAuthOutcome.confirmEmail:
            setState(() {
              _pendingConfirmEmail = email;
              _localNotice = AuthUserMessages.confirmEmailSent;
              _isSignUp = false;
            });
          case EmailAuthOutcome.accountExists:
            setState(() {
              _pendingConfirmEmail = null;
              _localNotice = null;
              _localError = AuthUserMessages.accountExists;
              _isSignUp = false;
            });
          case EmailAuthOutcome.failed:
            setState(() {
              _localError =
                  widget.supabase.errorMessage ??
                  AuthUserMessages.genericFailure;
            });
        }
        return;
      }

      final success = await widget.supabase.signInWithEmail(
        email: email,
        password: password,
      );
      if (!mounted) return;
      if (success) {
        SensoryFeedback.zenBloomPulse();
        widget.onAuthSuccess();
      } else {
        setState(() {
          _localError =
              widget.supabase.errorMessage ?? AuthUserMessages.genericFailure;
          if (_localError == AuthUserMessages.emailNotConfirmed) {
            _pendingConfirmEmail = email;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitLocked = false;
          _clearPassword();
        });
      }
    }
  }

  Future<void> _sendRecovery({bool confirmation = false}) async {
    if (_submitLocked) return;
    final email = _emailController.text.trim();
    final error = CredentialRules.validateEmail(email);
    if (error != null) {
      setState(() => _localError = error);
      return;
    }
    if (_lastRecoveryEmail != null &&
        DateTime.now().difference(_lastRecoveryEmail!).inSeconds < 60) {
      setState(
        () => _localNotice =
            'Please wait a minute before requesting another email.',
      );
      return;
    }
    setState(() {
      _submitLocked = true;
      _localError = null;
    });
    try {
      await widget.supabase.sendRecoveryEmail(
        email,
        confirmation: confirmation,
      );
      _lastRecoveryEmail = DateTime.now();
      if (mounted) {
        setState(
          () => _localNotice =
              'If this address is registered, an email is on its way. Check your spam folder too.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _localError = 'Email could not be sent. Please try again later.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitLocked = false);
    }
  }

  Widget _statusBanner({
    required String message,
    required Color color,
    required IconData icon,
    required Key key,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 16),
      child: EvenNotice(message: message, icon: icon, accent: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.supabase,
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final isBusy = widget.supabase.isLoading || _submitLocked;

        return Scaffold(
          backgroundColor: EvenColors.darkBackground,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const EvenBrandLockup(
                      markSize: 88,
                      wordSize: 28,
                      showTagline: true,
                    ),
                    const SizedBox(height: 28),

                    if (_localError != null)
                      _statusBanner(
                        key: const ValueKey('banner_auth_error'),
                        message: _localError!,
                        color: EvenColors.crashWarning,
                        icon: Icons.error_outline_rounded,
                      ),
                    if (_localNotice != null)
                      _statusBanner(
                        key: const ValueKey('banner_auth_notice'),
                        message: _localNotice!,
                        color: EvenColors.netSageLight,
                        icon: Icons.mark_email_read_outlined,
                      ),

                    // Auth Card
                    GlassCard(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Mode Selector (Sign In vs Sign Up)
                          Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.25)
                                  : Colors.white.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    key: const ValueKey('tab_sign_in'),
                                    onTap: () {
                                      SensoryFeedback.gentleTap();
                                      _switchAuthMode(false);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: !_isSignUp
                                            ? EvenColors.netSage.withValues(
                                                alpha: 0.3,
                                              )
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'Sign In',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: !_isSignUp
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: !_isSignUp
                                              ? EvenColors.netSageLight
                                              : (isDark
                                                    ? EvenColors.textDarkMuted
                                                    : EvenColors
                                                          .textLightMuted),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    key: const ValueKey('tab_sign_up'),
                                    onTap: () {
                                      SensoryFeedback.gentleTap();
                                      _switchAuthMode(true);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _isSignUp
                                            ? EvenColors.netSage.withValues(
                                                alpha: 0.3,
                                              )
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'Create Account',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: _isSignUp
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: _isSignUp
                                              ? EvenColors.netSageLight
                                              : (isDark
                                                    ? EvenColors.textDarkMuted
                                                    : EvenColors
                                                          .textLightMuted),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Email Field
                          TextField(
                            key: const ValueKey('input_email'),
                            controller: _emailController,
                            onChanged: (_) => setState(() {}),
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            decoration: InputDecoration(
                              hintText: 'Email address',
                              prefixIcon: const Icon(
                                Icons.email_outlined,
                                size: 20,
                              ),
                              filled: true,
                              fillColor: isDark
                                  ? Colors.black.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.4),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Password Field
                          TextField(
                            key: const ValueKey('input_password'),
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              hintText: 'Password',
                              helperText: _isSignUp
                                  ? CredentialRules.signUpHint
                                  : null,
                              helperMaxLines: 2,
                              helperStyle: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? EvenColors.textDarkMuted
                                    : EvenColors.textLightMuted,
                              ),
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                size: 20,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                              filled: true,
                              fillColor: isDark
                                  ? Colors.black.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.4),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Primary Action Button
                          ElevatedButton(
                            key: const ValueKey('btn_primary_auth'),
                            onPressed: isBusy ? null : _handleEmailAuth,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: EvenColors.netSage,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: isBusy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _isSignUp ? 'Create Account' : 'Sign In',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                          if (!_isSignUp)
                            TextButton(
                              key: const ValueKey('forgot_password'),
                              onPressed: isBusy ? null : () => _sendRecovery(),
                              child: const Text('Forgot password?'),
                            ),
                          if (_pendingConfirmEmail != null &&
                              _pendingConfirmEmail ==
                                  _emailController.text.trim())
                            TextButton(
                              key: const ValueKey('resend_confirmation'),
                              onPressed: isBusy
                                  ? null
                                  : () => _sendRecovery(confirmation: true),
                              child: const Text('Resend confirmation email'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'By continuing you agree to the ',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? EvenColors.textDarkMuted
                                : EvenColors.textLightMuted,
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('link_terms'),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LegalDocumentScreen.terms(),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Terms',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        Text(
                          ' and ',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? EvenColors.textDarkMuted
                                : EvenColors.textLightMuted,
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('link_privacy'),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LegalDocumentScreen.privacy(),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Privacy Policy',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        Text(
                          '.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? EvenColors.textDarkMuted
                                : EvenColors.textLightMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
