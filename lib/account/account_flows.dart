import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/auth_page.dart';
import 'account_service.dart';

/// Opens the sign-in page. Backup starts by itself once signed in.
Future<void> openSignIn(BuildContext context) async {
  final signedIn = await Navigator.of(
    context,
  ).push<bool>(MaterialPageRoute(builder: (_) => const SignInPage()));
  if (signedIn == true && context.mounted) {
    _snack(context, 'Signed in. Your reminders are being backed up.');
  }
}

/// Sign out, optionally removing reminders from this phone. Warns before
/// removing changes that haven't reached the backup yet.
Future<void> signOutFlow(BuildContext context) async {
  final remove = await _confirmWithRemoveOption(
    context,
    title: 'Sign out?',
    message:
        'Your reminders stay on this phone and keep ringing. Backup stops '
        'until you sign in again.',
    action: 'Sign out',
    removeByDefault: false,
  );
  if (remove == null || !context.mounted) return;

  final backedUp = await _withProgress(
    context,
    'Finishing backup…',
    AccountService.finishBackup,
  );
  if (!context.mounted) return;
  var removeFromPhone = remove;
  if (remove && !backedUp) {
    final choice = await _notBackedUpChoice(context);
    if (choice == null || !context.mounted) return;
    removeFromPhone = choice;
  }

  try {
    await _withProgress(
      context,
      'Signing out…',
      () => AccountService.signOut(removeFromPhone: removeFromPhone),
    );
  } catch (e) {
    debugPrint('Sign-out failed: $e');
    if (context.mounted) await _showError(context, "Couldn't sign out.");
    return;
  }
  if (!context.mounted) return;
  _snack(
    context,
    removeFromPhone
        ? 'Signed out. Reminders were removed from this phone.'
        : backedUp
        ? 'Signed out. Your reminders are still on this phone.'
        : 'Signed out. Recent changes are still on this phone and will be '
              'backed up next time you sign in.',
  );
}

/// Deletes the account and its backup after confirming it's the owner.
Future<void> deleteAccountFlow(BuildContext context) async {
  final remove = await _confirmWithRemoveOption(
    context,
    title: 'Delete your account?',
    message:
        'This permanently deletes your Snooze account and the backup of '
        "your reminders and history. It can't be undone.",
    action: 'Delete account',
    removeByDefault: true,
    destructive: true,
  );
  if (remove == null || !context.mounted) return;

  try {
    final confirmed = await AccountService.reauthenticate(
      askPassword: (email) => _askPassword(context, email),
    );
    if (!confirmed || !context.mounted) return;
    await _withProgress(
      context,
      'Deleting your account…',
      () => AccountService.deleteAccount(removeFromPhone: remove),
    );
    if (!context.mounted) return;
    _snack(
      context,
      remove
          ? 'Your account, backup and reminders were deleted.'
          : 'Your account and backup were deleted. Your reminders are '
                'still on this phone.',
    );
  } on AccountException catch (e) {
    if (context.mounted) await _showError(context, e.message);
  } catch (e) {
    debugPrint('Account deletion failed: $e');
    if (context.mounted) {
      await _showError(
        context,
        "Your account couldn't be deleted. Please try again.",
      );
    }
  }
}

/// A confirmation with an "Also remove reminders from this phone" option.
/// Returns that choice, or null if cancelled.
Future<bool?> _confirmWithRemoveOption(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  required bool removeByDefault,
  bool destructive = false,
}) {
  var remove = removeByDefault;
  return showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: remove,
                onChanged: (value) => setState(() => remove = value ?? false),
                title: const Text('Also remove reminders from this phone'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                    )
                  : null,
              onPressed: () => Navigator.pop(context, remove),
              child: Text(action),
            ),
          ],
        );
      },
    ),
  );
}

/// Offline at sign-out: removing reminders would lose changes that exist
/// only on this phone. Returns whether to remove them, or null to cancel.
Future<bool?> _notBackedUpChoice(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Some changes aren't backed up"),
      content: const Text(
        "Your latest changes haven't reached the backup (you may be "
        'offline). If you remove reminders from this phone now, those '
        'changes are lost.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove anyway'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep on this phone'),
        ),
      ],
    ),
  );
}

Future<String?> _askPassword(BuildContext context, String email) {
  if (!context.mounted) return Future.value();
  return showDialog<String>(
    context: context,
    builder: (_) => _PasswordDialog(email: email),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.email});

  final String email;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty) return;
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Confirm it's you"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter the password for ${widget.email}.'),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            autofocus: true,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Confirm')),
      ],
    );
  }
}

/// Runs [task] behind a progress dialog the user can't dismiss.
Future<T> _withProgress<T>(
  BuildContext context,
  String label,
  Future<T> Function() task,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    navigator.pop();
  }
}

Future<void> _showError(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
