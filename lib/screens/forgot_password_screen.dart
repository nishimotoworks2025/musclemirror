import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  // フェーズ: 'email' → 'reset'
  String _phase = 'email';
  bool _isLoading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _errorMessage;
  String? _successMessage;
  String _sentEmail = '';

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = '有効なメールアドレスを入力してください');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _authService.forgotPassword(email);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      setState(() {
        _sentEmail = email;
        _phase = 'reset';
        _successMessage = '$email にリセットコードを送信しました';
      });
    } else {
      setState(() => _errorMessage = result.errorMessage);
    }
  }

  Future<void> _handleResend() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final result = await _authService.forgotPassword(_sentEmail);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      setState(() => _successMessage = 'リセットコードを再送信しました');
    } else {
      setState(() => _errorMessage = result.errorMessage);
    }
  }

  Future<void> _handleResetPassword() async {
    final code = _codeController.text.trim();
    final newPass = _newPasswordController.text;
    final confirmPass = _confirmPasswordController.text;

    if (code.isEmpty) {
      setState(() => _errorMessage = '確認コードを入力してください');
      return;
    }
    if (newPass.length < 8) {
      setState(() => _errorMessage = 'パスワードは8文字以上必要です');
      return;
    }
    if (newPass != confirmPass) {
      setState(() => _errorMessage = 'パスワードが一致しません');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _authService.confirmForgotPassword(
      _sentEmail,
      code,
      newPass,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('パスワードを変更しました。新しいパスワードでログインしてください'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
      Navigator.of(context).pop();
    } else {
      setState(() => _errorMessage = result.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('パスワードのリセット'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _phase == 'email'
                ? _buildEmailPhase(theme, isDark)
                : _buildResetPhase(theme, isDark),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailPhase(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 80,
          height: 80,
          margin: const EdgeInsets.only(bottom: 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.brandBlue.withAlpha(30),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(Icons.lock_reset, size: 40, color: AppTheme.brandBlue),
        ),

        Text(
          'パスワードをお忘れですか？',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          '登録したメールアドレスを入力してください。\nパスワードリセット用のコードを送信します。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withAlpha(160),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          onFieldSubmitted: (_) => _handleSendCode(),
          decoration: InputDecoration(
            labelText: 'メールアドレス',
            hintText: 'example@email.com',
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: isDark ? Colors.white.withAlpha(13) : Colors.black.withAlpha(8),
          ),
        ),
        const SizedBox(height: 16),

        if (_errorMessage != null) ...[
          _buildMessageBox(isError: true, message: _errorMessage!),
          const SizedBox(height: 16),
        ],

        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _isLoading ? null : _handleSendCode,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'リセットコードを送信',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildResetPhase(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 80,
          height: 80,
          margin: const EdgeInsets.only(bottom: 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.orange.withAlpha(30),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.mark_email_read_outlined, size: 40, color: Colors.orange),
        ),

        Text(
          'コードを確認してください',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          '$_sentEmail\nにリセットコードを送信しました。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withAlpha(160),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // Code input
        TextFormField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
          decoration: InputDecoration(
            labelText: '確認コード',
            hintText: '123456',
            counterText: '',
            prefixIcon: const Icon(Icons.pin_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: isDark ? Colors.white.withAlpha(13) : Colors.black.withAlpha(8),
          ),
        ),
        const SizedBox(height: 16),

        // New Password
        AutofillGroup(
          child: Column(
            children: [
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscureNew,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: '新しいパスワード',
                  hintText: '8文字以上（大文字・小文字・数字を含む）',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNew
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: isDark ? Colors.white.withAlpha(13) : Colors.black.withAlpha(8),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onFieldSubmitted: (_) => _handleResetPassword(),
                decoration: InputDecoration(
                  labelText: '新しいパスワード（確認）',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: isDark ? Colors.white.withAlpha(13) : Colors.black.withAlpha(8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_successMessage != null) ...[
          _buildMessageBox(isError: false, message: _successMessage!),
          const SizedBox(height: 12),
        ],
        if (_errorMessage != null) ...[
          _buildMessageBox(isError: true, message: _errorMessage!),
          const SizedBox(height: 12),
        ],

        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _isLoading ? null : _handleResetPassword,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'パスワードを変更する',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 16),

        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('コードを再送信'),
            onPressed: _isLoading ? null : _handleResend,
          ),
        ),
        Center(
          child: TextButton(
            onPressed: () => setState(() {
              _phase = 'email';
              _errorMessage = null;
              _successMessage = null;
            }),
            child: Text(
              '← メールアドレスを変更する',
              style: TextStyle(color: theme.textTheme.bodySmall?.color?.withAlpha(180)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBox({required bool isError, required String message}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isError ? Colors.red : Colors.green).withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (isError ? Colors.red : Colors.green).withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? Colors.red : Colors.green,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: isError ? Colors.red : Colors.green),
            ),
          ),
        ],
      ),
    );
  }
}
