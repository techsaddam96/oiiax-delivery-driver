import 'package:blockatie/provider/login.dart';
import 'package:blockatie/utils/password_policy.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shown after signing in with an admin-issued temporary password.
///
/// Nothing else in the app is reachable from here: the server returned no
/// api_key, only the single-purpose [changeToken], which lives in this widget's
/// memory and is never stored. Leaving the page returns to the login screen.
class ForcedPasswordChangePage extends StatefulWidget {
  const ForcedPasswordChangePage({super.key, required this.changeToken});

  final String changeToken;

  @override
  State<ForcedPasswordChangePage> createState() =>
      _ForcedPasswordChangePageState();
}

class _ForcedPasswordChangePageState extends State<ForcedPasswordChangePage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  String? _error;

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  String _t(String en, String ar) => _isArabic ? ar : en;

  @override
  void dispose() {
    _password.clear();
    _confirm.clear();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _error = null);
    final error = await context.read<LoginProvider>().completeForcedPasswordChange(
      changeToken: widget.changeToken,
      newPassword: _password.text,
      confirmPassword: _confirm.text,
    );
    if (!mounted) return;
    if (error != null) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<LoginProvider>().isChangingPassword;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_t('Set a new password', 'تعيين كلمة مرور جديدة'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _t(
                    'You signed in with a temporary password. Choose a new password to continue.',
                    'سجّلت الدخول بكلمة مرور مؤقتة. اختر كلمة مرور جديدة للمتابعة.',
                  ),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  PasswordPolicy.rules(isArabic: _isArabic),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const Key('forcedNewPassword'),
                  controller: _password,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: _t('New password', 'كلمة المرور الجديدة'),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (value) => PasswordPolicy.message(value, isArabic: _isArabic),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('forcedConfirmPassword'),
                  controller: _confirm,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: _t('Confirm password', 'تأكيد كلمة المرور'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => value != _password.text
                      ? _t('Passwords do not match.', 'كلمتا المرور غير متطابقتين.')
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('forcedChangeError'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  key: const Key('forcedSubmit'),
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_t('Save and continue', 'حفظ ومتابعة')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
