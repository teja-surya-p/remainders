import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account/google_auth.dart';
import '../components/common/app_ui.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../user_store.dart';

/// Optional sign-in, opened from Profile: it turns on backup. Closes itself
/// with `true` once signed in.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  static final RegExp _emailPattern = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _isLogin = true;
  bool _showPassword = false;
  bool _loading = false;
  String? _error;
  String? _lastEmail;
  String? _emailFieldError;
  String? _passwordFieldError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadLastUser();
  }

  Future<void> _loadLastUser() async {
    final email = await UserStore.lastEmail();
    if (!mounted) return;
    setState(() {
      _lastEmail = email;
      if (_email.text.isEmpty && email != null) {
        _email.text = email;
      }
    });
  }

  Future<void> _handleEmail() async {
    final email = _email.text.trim();
    final password = _password.text;

    final emailError = _validateEmail(email);
    final passwordError = _validatePassword(password);
    if (emailError != null || passwordError != null) {
      setState(() {
        _emailFieldError = emailError;
        _passwordFieldError = passwordError;
        _error = emailError ?? passwordError;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _emailFieldError = null;
      _passwordFieldError = null;
    });

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
      _done();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Auth failed.');
    } catch (e) {
      setState(() => _error = 'Auth failed: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _handleGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      } else {
        final credential = await GoogleAuth.credential();
        if (credential == null) {
          setState(() => _loading = false);
          return;
        }
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
      _done();
    } on PlatformException catch (e) {
      setState(() => _error = _friendlyGoogleError(e));
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Google sign-in failed.');
    } catch (e) {
      setState(() => _error = 'Google sign-in failed: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _email.text.trim();
    final emailError = _validateEmail(email);
    if (emailError != null) {
      setState(() {
        _emailFieldError = emailError;
        _error = 'Enter a valid email first, then tap Forgot password.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent to $email')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message ?? 'Unable to send reset email.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Unable to send reset email: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _friendlyGoogleError(PlatformException e) {
    final message = (e.message ?? '').toLowerCase();
    final isApi10 =
        e.code == 'sign_in_failed' &&
        (message.contains('apiexception: 10') ||
            message.contains('developer_error'));
    if (isApi10) {
      return 'Google Sign-In is not configured for this Android signing key yet. '
          'Add your SHA-1 in Firebase (Project Settings > Android app), '
          'download updated google-services.json, then rebuild.';
    }
    return 'Google sign-in failed: ${e.message ?? e.code}';
  }

  String? _validateEmail(String email) {
    final value = email.trim();
    if (value.isEmpty) {
      return 'Email is required.';
    }
    if (value.contains(' ')) {
      return 'Email cannot contain spaces.';
    }
    if (!_emailPattern.hasMatch(value)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String password) {
    if (password.isEmpty) {
      return 'Password is required.';
    }
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    return null;
  }

  /// Signed in: back to where the user came from.
  void _done() {
    if (!mounted) return;
    Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = AppTone.of(context);

    return Scaffold(
      body: Stack(
        children: [
          Container(color: Theme.of(context).scaffoldBackgroundColor),
          Positioned(
            left: -90,
            top: -120,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            right: -70,
            top: 120,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withValues(alpha: 0.08),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AppSurfaceCard(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    child: AnimatedSwitcher(
                      duration: AppMotion.page,
                      switchInCurve: AppMotion.emphasized,
                      switchOutCurve: AppMotion.standard,
                      child: Column(
                        key: ValueKey(_isLogin),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: cs.primary,
                                  boxShadow: [
                                    BoxShadow(
                                      color: cs.primary.withValues(alpha: 0.26),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.notifications_active_rounded,
                                  color: cs.onPrimary,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Snooze',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    Text(
                                      _isLogin
                                          ? 'Welcome back'
                                          : 'Create your account',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: tone.mutedText),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Sign in to back up your reminders and get them '
                            'back on a new phone. Snooze works without an '
                            'account too.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: tone.mutedText),
                          ),
                          if (!_isLogin) ...[
                            const SizedBox(height: 12),
                            TextField(
                              enabled: !_loading,
                              decoration: const InputDecoration(
                                labelText: 'Full name',
                                hintText: 'Your name',
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            controller: _email,
                            enabled: !_loading,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            onChanged: (value) {
                              if (_emailFieldError != null) {
                                setState(
                                  () =>
                                      _emailFieldError = _validateEmail(value),
                                );
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Email',
                              hintText: _lastEmail ?? 'you@example.com',
                              helperText:
                                  'Use a valid email like name@example.com',
                              errorText: _emailFieldError,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _password,
                            enabled: !_loading,
                            obscureText: !_showPassword,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) {
                              if (!_loading) {
                                _handleEmail();
                              }
                            },
                            onChanged: (value) {
                              if (_passwordFieldError != null) {
                                setState(
                                  () => _passwordFieldError = _validatePassword(
                                    value,
                                  ),
                                );
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Password',
                              helperText: 'Minimum 8 characters',
                              errorText: _passwordFieldError,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                ),
                                onPressed: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                              ),
                            ),
                          ),
                          if (_isLogin) ...[
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _loading
                                    ? null
                                    : _handleForgotPassword,
                                child: const Text('Forgot password?'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: _loading ? null : _handleEmail,
                            child: _loading
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                        cs.onPrimary,
                                      ),
                                    ),
                                  )
                                : Text(_isLogin ? 'Sign In' : 'Create Account'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _handleGoogle,
                            icon: const Icon(
                              Icons.g_mobiledata_rounded,
                              size: 24,
                            ),
                            label: const Text('Continue with Google'),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => setState(() {
                                    _isLogin = !_isLogin;
                                    _error = null;
                                    _emailFieldError = null;
                                    _passwordFieldError = null;
                                  }),
                            child: Text(
                              _isLogin
                                  ? 'Need an account? Sign up'
                                  : 'Have an account? Sign in',
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            AppInlineMessage(
                              text: _error!,
                              icon: Icons.error_outline_rounded,
                              color: cs.error,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (Navigator.of(context).canPop())
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
