import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import '../services/billing_service.dart';

/// Subscription page for purchasing Pro subscription plans
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final BillingService _billingService = BillingService();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeBilling();
  }

  Future<void> _initializeBilling({bool forceReload = false}) async {
    setState(() => _isLoading = true);
    await _billingService.initialize(forceReload: forceReload);
    setState(() => _isLoading = false);
  }

  Future<void> _purchaseSubscription(ProductDetails product) async {
    await _doPurchase(() => _billingService.purchaseBasePlan(product));
  }

  Future<void> _purchaseTicket() async {
    await _doPurchase(() => _billingService.purchaseConsumable(ProductIds.ticket));
  }

  Future<void> _doPurchase(Future<bool> Function() purchaseFn) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await purchaseFn();
      if (!success && mounted) {
        setState(() {
          _errorMessage = '購入処理を開始できませんでした';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '購入中にエラーが発生しました: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  ProductDetails? _getProduct(String productId) {
    try {
      return _billingService.products.firstWhere((p) => p.id == productId);
    } catch (_) {
      return null;
    }
  }

  // Helfer for Google Play Base Plans
  ProductDetails? _getAndroidBasePlan(String productId, String basePlanId) {
    try {
      for (final p in _billingService.products) {
        if (p.id == productId && p is GooglePlayProductDetails) {
          final subscriptionOfferDetails = p.productDetails.subscriptionOfferDetails;
          if (subscriptionOfferDetails != null) {
            final hasBasePlan = subscriptionOfferDetails.any(
                (offer) => offer.basePlanId == basePlanId);
            if (hasBasePlan) return p;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Fallback: iOS or old Android logic (Gets first ProductDetails)
    ProductDetails? proProduct = _getProduct(ProductIds.pro);
    
    // Identify specific base plans for Android 5+
    ProductDetails? monthlyProProduct = _getAndroidBasePlan(ProductIds.pro, 'musclemirror-month-v2') ?? proProduct;
    ProductDetails? yearlyProProduct = _getAndroidBasePlan(ProductIds.pro, 'musclemirror-year') ?? proProduct;
    
    final ticketProduct = _getProduct(ProductIds.ticket);
    final hasAnyProduct = proProduct != null || ticketProduct != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('プラン・チケット購入'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Debug Info (Only visible if something is wrong)
            if (!_billingService.isAvailable && !_isLoading)
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withAlpha(100)),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          '課金サービスが利用不可',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'デバッグモードの場合、エミュレータではなくGoogle Playが動作する実機でテストしてください。',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),

            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withAlpha(180),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.workspace_premium,
                    size: 64,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Muscle Mirror Pro',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'すべての機能にアクセス',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),

            // Pro Features
            Text(
              'Proプランの特典',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _FeatureItem(
              icon: Icons.fitness_center,
              title: '詳細な筋肉分析',
              description: '全身の筋肉バランスを詳しく評価',
            ),
            _FeatureItem(
              icon: Icons.trending_up,
              title: '進捗トラッキング',
              description: '長期間の進捗をグラフで可視化',
            ),
            _FeatureItem(
              icon: Icons.history,
              title: '無制限の履歴',
              description: 'すべての判定履歴を保存',
            ),
            _FeatureItem(
              icon: Icons.star,
              title: '優先サポート',
              description: 'プレミアムユーザー向けサポート',
            ),

            const SizedBox(height: 32),

            // Error message
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withAlpha(50)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Purchase Plans
            Text(
              'プランを選択',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Google Play から商品を読み込み中...'),
                    ],
                  ),
                ),
              )
            else if (!hasAnyProduct)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withAlpha(100),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.search_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      '商品情報を取得できませんでした',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Debug Info:\n${_billingService.debugInfo}'
                        '\nNot Found IDs: ${_billingService.notFoundIDs}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _initializeBilling(forceReload: true),
                      icon: const Icon(Icons.refresh),
                      label: const Text('強制再読み込み'),
                    ),
                  ],
                ),
              )
            else ...[
              // 1. Monthly Pro Subscription
              if (monthlyProProduct != null) ...[
                _SubscriptionCard(
                  title: '月額プラン',
                  price: monthlyProProduct.price,
                  description: '毎月自動更新・すべての機能が使い放題',
                  isLoading: _isLoading,
                  onTap: () => _purchaseSubscription(monthlyProProduct),
                ),
                
                const SizedBox(height: 12),

                // 2. Yearly Pro Subscription (recommended)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _SubscriptionCard(
                      title: '年額プラン',
                      price: '¥4,800', // Override the price string from the store to ensure it displays correctly
                      description: '毎年自動更新（2ヶ月分お得！）',
                      isPopular: true,
                      isLoading: _isLoading,
                      onTap: yearlyProProduct != null ? () => _purchaseSubscription(yearlyProProduct) : null,
                    ),
                    Positioned(
                      top: -10,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withAlpha(80),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Text(
                          'おすすめ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
              ],

              // 3. One-time Ticket
              if (ticketProduct != null)
                _SubscriptionCard(
                  title: '1回分チケット',
                  price: ticketProduct.price,
                  description: '1回分の判定チケット',
                  icon: Icons.confirmation_number,
                  isLoading: _isLoading,
                  onTap: _purchaseTicket,
                ),
            ],

            const SizedBox(height: 24),

            // Restore purchases
            TextButton(
              onPressed: _isLoading ? null : () async {
                setState(() => _isLoading = true);
                try {
                  await _billingService.restorePurchases();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('購入の復元プロセスを開始しました')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('復元中にエラーが発生しました: $e')),
                    );
                  }
                } finally {
                  if (mounted) {
                    setState(() => _isLoading = false);
                  }
                }
              },
              child: const Text('以前の購入を復元'),
            ),

            const SizedBox(height: 16),

            // Legal text
            Text(
              '・購入確定時にGoogle Playアカウントに請求されます\n'
              '・現在の期間終了の24時間以上前に自動更新をオフにしない限り、サブスクリプションは自動的に更新されます\n'
              '・サブスクリプションはGoogle Play設定から管理・解約できます',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withAlpha(150),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: theme.colorScheme.primary,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withAlpha(150),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final String title;
  final String price;
  final String description;
  final bool isPopular;
  final bool isLoading;
  final IconData? icon;
  final VoidCallback? onTap;

  const _SubscriptionCard({
    required this.title,
    required this.price,
    required this.description,
    this.isPopular = false,
    this.isLoading = false,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: isPopular ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isPopular 
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      price,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withAlpha(150),
                      ),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.arrow_forward_ios,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
