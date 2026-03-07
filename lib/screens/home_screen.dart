import 'package:flutter/material.dart';
import '../main.dart';
import '../models/muscle_data.dart';
import 'overview_tab.dart';
import 'detailed_tab.dart';
import 'progress_tab.dart';
import 'history_tab.dart';
import 'diagnosis_screen.dart';
import 'login_screen.dart';
import 'subscription_page.dart';
import '../services/auth_service.dart';
import '../services/history_service.dart';
import '../services/user_mode_service.dart';
import '../services/usage_limit_service.dart';
import '../services/billing_service.dart';
import '../config/app_config.dart';
import '../widgets/user_mode_indicator.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  MuscleEvaluation? _currentEvaluation;
  List<MuscleEvaluation> _evaluationHistory = [];
  final UserModeService _userModeService = UserModeService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  final EvaluationType _evaluationType = EvaluationType.balanced;
  int _remainingCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _userModeService.initialize();
    _userModeService.modeStream.listen((_) {
      if (mounted) {
        setState(() {});
        _updateRemainingCount();
      }
    });
    _loadHistory();
    _updateRemainingCount();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _updateRemainingCount() async {
    final count = await _usageLimitService.getRemainingCount();
    if (mounted) setState(() => _remainingCount = count);
  }

  Future<void> _loadHistory() async {
    final history = await HistoryService.loadEvaluations();
    if (mounted) {
      setState(() {
        _evaluationHistory = history;
        if (_evaluationHistory.isNotEmpty) {
          _currentEvaluation = _evaluationHistory.last;
        } else {
          // Keep a sample if empty, or leave null
          _currentEvaluation = null;
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && AuthService().isAuthenticated) {
      debugPrint('HomeScreen: App resumed, syncing subscription status...');
      BillingService().syncWithServer().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _showSettingsSheet() {
    final appState = MuscleMirrorApp.of(context);
    if (appState == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SettingsSheet(
        currentThemeModeIndex: appState.currentThemeModeIndex,
        onThemeModeChanged: appState.setThemeMode,
        isPro: _userModeService.isPro,
        userMode: _userModeService.currentMode,
        onLogout: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('ログアウト'),
              content: const Text('ログアウトしてもよろしいですか？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(
                    'ログアウト',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          );

          if (confirm == true) {
            await AuthService().signOut();
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            }
          }
        },
        onDeleteAccount: () async {
          final billingService = BillingService();
          await billingService.syncWithServer();
          if (!mounted) return;

          final isProSub = billingService.hasActiveSubscription;
          final planStatus = billingService.meStatus?.planStatus;
          final requiresCancellation = isProSub && planStatus != 'cancelled';

          if (requiresCancellation) {
            await showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('解約手続きが必要です'),
                content: const Text(
                  '現在は確認のみです。\\n'
                  '解約手続きをしてください。\n\n'
                  'サブスクリプションを解約するまで、アカウント削除は実行できません。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
            return;
          }

          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('アカウント削除', style: TextStyle(color: Colors.red)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('アカウントを削除すると、すべての履歴データが失われます。この操作は取り消せません。'),
                  if (isProSub) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withAlpha(40),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.amber),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '【重要】Proプランの定期購入は自動的にキャンセルされません。削除前に必ずストア設定より解約手続きを行ってください。',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('本当に続行しますか？'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(
                    '削除する',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          );

          if (confirm == true) {
            final result = await AuthService().deleteAccount();
            if (mounted) {
              if (result.success) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('アカウントを削除しました')));
              } else {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('エラー'),
                    content: Text(
                      result.errorMessage ?? 'アカウントの削除中にエラーが発生しました',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              }
            }
          }
        },
      ),
    );
  }

  Future<void> _startDiagnosis() async {
    // Check usage limit
    final canUse = await _usageLimitService.canUse();
    if (!canUse) {
      if (!mounted) return;
      _showUsageLimitDialog();
      return;
    }

    final result = await Navigator.of(context).push<MuscleEvaluation>(
      MaterialPageRoute(
        builder: (_) => DiagnosisScreen(
          evaluationType: _evaluationType,
          isPro: _userModeService.isPro || _userModeService.isGuest,
        ),
        fullscreenDialog: true,
      ),
    );

    if (result != null) {
      if (!mounted) return;

      // Consume a ticket if the user is relying on it
      // The user is relying on a ticket if they are in Pro mode but do not have an active subscription
      bool ticketConsumed = false;
      if (_userModeService.isPro) {
        final billingService = BillingService();
        if (!billingService.hasActiveSubscription &&
            billingService.ticketCount > 0) {
          await billingService.consumeTicket();
          ticketConsumed = true;
        }
      }

      // Record usage after successful diagnosis (only if ticket was not used, to save their free trial)
      if (!ticketConsumed) {
        await _usageLimitService.recordUse();
      }

      setState(() {
        _currentEvaluation = result;
        _evaluationHistory.add(result);
        _tabController.animateTo(0);
      });

      // Save newly added evaluation
      await HistoryService.saveEvaluations(_evaluationHistory);

      // Update remaining count
      await _updateRemainingCount();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('判定が完了しました！')));
    }
  }

  void _showUsageLimitDialog() {
    final mode = _userModeService.currentMode;

    switch (mode) {
      case UserMode.guest:
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange),
                SizedBox(width: 8),
                Text('利用上限に達しました'),
              ],
            ),
            content: const Text(
              'ゲストモードでの判定回数（合計3回）に達しました。\n\n'
              'ログインすると毎日1回まで判定できます。\n'
              'Proプランにアップグレードすると、毎日3回まで利用可能です。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                icon: const Icon(Icons.login),
                label: const Text('ログイン'),
              ),
            ],
          ),
        );
        break;
      case UserMode.free:
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange),
                SizedBox(width: 8),
                Text('本日の利用上限'),
              ],
            ),
            content: const Text(
              '無料プランの本日の判定回数（1回）に達しました。\n\n'
              'Proプランにアップグレードすると、毎日3回まで利用可能です。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SubscriptionPage()),
                  );
                },
                icon: const Icon(Icons.workspace_premium),
                label: const Text('Proにアップグレード'),
              ),
            ],
          ),
        );
        break;
      case UserMode.pro:
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 8),
                Text('本日の利用上限'),
              ],
            ),
            content: const Text(
              'Proプランの本日の判定回数（3回）に達しました。\n\n'
              '明日になるとカウントがリセットされます。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        break;
    }
  }

  void _selectEvaluation(int index) {
    if (index >= 0 && index < _evaluationHistory.length) {
      setState(() {
        _currentEvaluation = _evaluationHistory[index];
        // Switch to Overview tab to show selected evaluation
        _tabController.animateTo(0);
      });
    }
  }

  void _deleteEvaluation(int index) {
    if (index >= 0 && index < _evaluationHistory.length) {
      setState(() {
        final deleted = _evaluationHistory.removeAt(index);
        if (_currentEvaluation == deleted) {
          _currentEvaluation = _evaluationHistory.isNotEmpty
              ? _evaluationHistory.last
              : null;
        }
      });

      // Update local storage after deletion
      HistoryService.saveEvaluations(_evaluationHistory);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('履歴を削除しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Muscle Mirror'),
        actions: [
          UserModeIndicator(onProTap: _showSettingsSheet),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showSettingsSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '概要'),
            Tab(text: '詳細'),
            Tab(text: '進捗'),
            Tab(text: '履歴'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          OverviewTab(
            evaluation: _currentEvaluation,
            evaluationType: _evaluationType,
            evaluations: _evaluationHistory,
          ),
          DetailedTab(
            evaluation: _currentEvaluation,
            userMode: _userModeService.currentMode,
          ),
          ProgressTab(
            evaluations: _evaluationHistory,
            userMode: _userModeService.currentMode,
          ),
          HistoryTab(
            evaluations: _evaluationHistory,
            onEvaluationSelected: _selectEvaluation,
            onEvaluationDeleted: _deleteEvaluation,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startDiagnosis,
        icon: const Icon(Icons.camera_alt),
        label: Text('判定する（残り$_remainingCount回）'),
      ),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  final int currentThemeModeIndex;
  final Future<void> Function(int) onThemeModeChanged;
  final bool isPro;
  final UserMode userMode;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  const _SettingsSheet({
    required this.currentThemeModeIndex,
    required this.onThemeModeChanged,
    required this.isPro,
    required this.userMode,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('設定', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 24),

            // Subscription Section
            if (userMode != UserMode.guest) ...[
              Text('サブスクリプション', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              if (isPro)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.workspace_premium, color: Colors.amber),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              BillingService().hasActiveSubscription
                                  ? (BillingService().meStatus?.planStatus ==
                                                'cancelled' ||
                                            BillingService()
                                                        .meStatus
                                                        ?.planStatus ==
                                                    'none' &&
                                                BillingService()
                                                        .meStatus
                                                        ?.expiresAt !=
                                                    null
                                        ? 'Proプラン（解約済み）'
                                        : 'Proプラン利用中')
                                  : '1回分チケット適用中',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              BillingService().hasActiveSubscription
                                  ? (BillingService().meStatus?.expiresAt !=
                                            null
                                        ? '${BillingService().meStatus!.expiresAt} まで有効'
                                        : 'すべての機能にアクセスできます')
                                  : '残り ${BillingService().ticketCount} 枚のチケットがあります',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: () async {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ステータスを更新中...')),
                          );
                          await BillingService().syncWithServer();
                          if (context.mounted) {
                            Navigator.pop(context); // Close sheet to refresh UI
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('ステータスを更新しました')),
                            );
                          }
                        },
                        tooltip: 'ステータスを更新',
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SubscriptionPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.workspace_premium),
                    label: const Text('Proプランにアップグレード'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              _SettingsLinkTile(
                icon: Icons.credit_card,
                title: '定期購入の管理',
                subtitle: 'Manage Subscriptions',
                onTap: () => _openUrl(
                  'https://play.google.com/store/account/subscriptions',
                ),
              ),
              const Divider(height: 32),
            ],

            // Theme Mode
            Text('テーマ', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('システム')),
                ButtonSegment(value: 1, label: Text('ライト')),
                ButtonSegment(value: 2, label: Text('ダーク')),
              ],
              selected: {currentThemeModeIndex},
              onSelectionChanged: (selected) {
                onThemeModeChanged(selected.first);
              },
            ),

            const SizedBox(height: 32),

            // Logout Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout),
                label: const Text('ログアウト'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Delete Account Button
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: onDeleteAccount,
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                label: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'アカウント削除',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '端末内データとサーバー上のアカウントが削除されます',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.redAccent.withAlpha(150),
                      ),
                    ),
                  ],
                ),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const Divider(height: 32),

            // Legal & Policy Section
            Text(
              '利用規約・ポリシー',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.textTheme.bodySmall?.color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            _SettingsLinkTile(
              icon: Icons.description_outlined,
              title: '利用規約',
              subtitle: 'Terms of Service',
              onTap: () => _openUrl(AppConfig.termsOfServiceUrl),
            ),
            _SettingsLinkTile(
              icon: Icons.privacy_tip_outlined,
              title: 'プライバシーポリシー',
              subtitle: 'Privacy Policy',
              onTap: () => _openUrl(AppConfig.privacyPolicyUrl),
            ),
            _SettingsLinkTile(
              icon: Icons.mail_outline,
              title: 'お問い合わせ',
              subtitle: 'Contact / Support',
              onTap: () => _openUrl(AppConfig.contactUrl),
            ),
            _SettingsLinkTile(
              icon: Icons.info_outline,
              title: 'アカウント削除について',
              subtitle: 'Account Deletion',
              onTap: () => _openUrl(AppConfig.accountDeletionUrl),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SettingsLinkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsLinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.textTheme.bodySmall?.color?.withAlpha(150),
        ),
      ),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
