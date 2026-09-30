import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/telemetry.dart';
import '../../core/security/credential_rules.dart';
import '../../services/supabase_service.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  final SupabaseService supabase;
  const PasswordRecoveryScreen({super.key, required this.supabase});
  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final error = CredentialRules.validateSignUp(
      email: widget.supabase.currentUser?.email ?? 'user@example.com',
      password: _password.text,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.supabase.completePasswordRecovery(_password.text);
    } catch (error) {
      Telemetry.report(
        name: 'auth.password_update_failed',
        tags: {
          'kind': error is TimeoutException
              ? 'timeout'
              : error.runtimeType.toString(),
        },
      );
      if (mounted) {
        setState(
          () => _error = error is TimeoutException
              ? 'The update could not be confirmed yet. Your password may have changed. Wait a moment, or sign out and try your new password.'
              : error is AuthException && error.code == 'same_password'
              ? 'Choose a password different from your current password.'
              : error is AuthException &&
                    (error.code == 'session_not_found' ||
                        error.code == 'refresh_token_not_found' ||
                        error is AuthSessionMissingException)
              ? 'Your reset session has expired. Request a new reset email.'
              : 'The update could not be confirmed. Try signing in with your new password before requesting another reset email.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reset password')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New password',
              helperText: CredentialRules.signUpHint,
              helperMaxLines: 2,
            ),
          ),
          if (_error != null) Text(_error!),
          ElevatedButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving...' : 'Save password'),
          ),
          TextButton(
            onPressed: _busy ? null : widget.supabase.signOut,
            child: const Text('Cancel and sign out'),
          ),
        ],
      ),
    ),
  );
}
