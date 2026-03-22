import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _codeController = TextEditingController();
  final _authService = AuthService();

  // フェーズ: 'register' or 'confirm'
  String _phase = 'register';
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;
  String? _successMessage;
  String _registeredEmail = ''; // 表示用
  String _registeredUsername = ''; // Cognito操作用（生成されたusername）

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _authService.signUp(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      setState(() {
        _registeredEmail = _emailController.text.trim();
        _registeredUsername = result.data ?? _emailController.text.trim();
        _phase = 'confirm';
        _successMessage = '確認コードを $_registeredEmail に送信しました';
      });
    } else {
      setState(() => _errorMessage = result.errorMessage);
    }
  }

  Future<void> _handleConfirm() async {
    if (_codeController.text.trim().isEmpty) {
      setState(() => _errorMessage = '確認コードを入力してください');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _authService.confirmSignUp(
      _registeredUsername,
      _codeController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('登録が完了しました！メールアドレスとパスワードでログインしてください'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
      Navigator.of(context).pop();
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

    final result = await _authService.resendConfirmationCode(
      _registeredUsername,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      setState(() => _successMessage = '確認コードを再送信しました');
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
        title: Text(_phase == 'register' ? '新規登録' : 'メール確認'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _phase == 'register'
                ? _buildRegisterForm(theme, isDark)
                : _buildConfirmForm(theme, isDark),
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterForm(ThemeData theme, bool isDark) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            width: 80,
            height: 80,
            margin: const EdgeInsets.only(bottom: 24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.brandBlue, AppTheme.brandBlue.withAlpha(180)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.brandBlue.withAlpha(50),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.person_add_alt_1,
              size: 40,
              color: Colors.white,
            ),
          ),

          Text(
            'アカウント作成',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'メールアドレスとパスワードを入力してください',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withAlpha(150),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Email
          AutofillGroup(
            child: Column(
              children: [
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: 'メールアドレス',
                    hintText: 'example@email.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withAlpha(13)
                        : Colors.black.withAlpha(8),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'メールアドレスを入力してください';
                    }
                    if (!value.contains('@')) {
                      return '有効なメールアドレスを入力してください';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Password
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'パスワード',
                    hintText: '8文字以上（大文字・小文字・数字を含む）',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withAlpha(13)
                        : Colors.black.withAlpha(8),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'パスワードを入力してください';
                    }
                    if (value.length < 8) {
                      return 'パスワードは8文字以上必要です';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Confirm Password
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onFieldSubmitted: (_) => _handleRegister(),
                  decoration: InputDecoration(
                    labelText: 'パスワード（確認）',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withAlpha(13)
                        : Colors.black.withAlpha(8),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'パスワード（確認）を入力してください';
                    }
                    if (value != _passwordController.text) {
                      return 'パスワードが一致しません';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Error message
          if (_errorMessage != null) ...[
            _buildMessageBox(isError: true, message: _errorMessage!),
            const SizedBox(height: 16),
          ],

          // Register button
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _isLoading ? null : _handleRegister,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '登録する',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('すでにアカウントをお持ちの方は', style: theme.textTheme.bodySmall),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('ログイン'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmForm(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header icon
        Container(
          width: 80,
          height: 80,
          margin: const EdgeInsets.only(bottom: 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.green.withAlpha(30),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            size: 40,
            color: Colors.green,
          ),
        ),

        Text(
          'メールを確認してください',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          '$_registeredEmail\nに6桁の確認コードを送信しました。\nコードを入力して登録を完了してください。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withAlpha(170),
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
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
          ),
          decoration: InputDecoration(
            labelText: '確認コード',
            hintText: '123456',
            counterText: '',
            prefixIcon: const Icon(Icons.pin_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: isDark
                ? Colors.white.withAlpha(13)
                : Colors.black.withAlpha(8),
          ),
        ),
        const SizedBox(height: 16),

        // Success / Error messages
        if (_successMessage != null) ...[
          _buildMessageBox(isError: false, message: _successMessage!),
          const SizedBox(height: 12),
        ],
        if (_errorMessage != null) ...[
          _buildMessageBox(isError: true, message: _errorMessage!),
          const SizedBox(height: 12),
        ],

        // Confirm button
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _isLoading ? null : _handleConfirm,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    '確認する',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),

        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('確認コードを再送信'),
            onPressed: _isLoading ? null : _handleResend,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => setState(() {
              _phase = 'register';
              _errorMessage = null;
              _successMessage = null;
            }),
            child: Text(
              '← 登録情報を変更する',
              style: TextStyle(
                color: theme.textTheme.bodySmall?.color?.withAlpha(180),
              ),
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
        border: Border.all(
          color: (isError ? Colors.red : Colors.green).withAlpha(80),
        ),
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
