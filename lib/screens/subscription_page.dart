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

  void _refreshEntitlementView() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _billingService.isProNotifier.addListener(_refreshEntitlementView);
    _initializeBilling();
  }

  @override
  void dispose() {
    _billingService.isProNotifier.removeListener(_refreshEntitlementView);
    super.dispose();
  }

  Future<void> _initializeBilling({bool forceReload = false}) async {
    setState(() => _isLoading = true);
    await _billingService.initialize(forceReload: forceReload);
    setState(() => _isLoading = false);
  }

  Future<void> _purchaseTicket() async {
    await _doPurchase(
      () => _billingService.purchaseConsumable(ProductIds.ticket),
    );
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

  // Helper for Google Play Base Plans
  ({String? offerToken, String? price}) _getPlanInfo(
    ProductDetails? product,
    String basePlanId,
  ) {
    if (product == null) return (offerToken: null, price: null);

    if (product is GooglePlayProductDetails) {
      final subscriptionOfferDetails =
          product.productDetails.subscriptionOfferDetails;
      if (subscriptionOfferDetails != null &&
          subscriptionOfferDetails.isNotEmpty) {
        debugPrint(
          '[SubscriptionPage] Product ${product.id} has ${subscriptionOfferDetails.length} offers.',
        );

        // 1. Try to find the exact base plan
        try {
          final offer = subscriptionOfferDetails.firstWhere(
            (offer) => offer.basePlanId == basePlanId,
          );
          final price = offer.pricingPhases.last.formattedPrice;
          debugPrint(
            '[SubscriptionPage] Found exact base plan $basePlanId: $price',
          );
          return (offerToken: offer.offerIdToken, price: price);
        } catch (_) {
          debugPrint(
            '[SubscriptionPage] Base plan $basePlanId not found for ${product.id}. Fallback to first offer.',
          );
        }

        // 2. Fallback to the first available offer if specific one not found
        final firstOffer = subscriptionOfferDetails.first;
        final price = firstOffer.pricingPhases.last.formattedPrice;
        debugPrint(
          '[SubscriptionPage] Fallback offer: ${firstOffer.basePlanId}, price: $price',
        );
        return (offerToken: firstOffer.offerIdToken, price: price);
      }
    }
    return (offerToken: null, price: product.price);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Fallback: iOS or old Android logic (Gets first ProductDetails)
    // Identify specific plans
    final proProduct = _getProduct(ProductIds.pro);

    // Try specialized standalone IDs first (Android/iOS)
    final ProductDetails? yearlyStandalone = _getProduct(ProductIds.proYearly);
    final ProductDetails? monthlyStandalone = _getProduct(
      ProductIds.proMonthlyV2,
    );

    // Fallback: If not found as standalone, check if they are base plans of the old 'pro' ID (Android 5+)
    final yearlyInfo = _getPlanInfo(
      yearlyStandalone ?? proProduct,
      'musclemirror-year',
    );
    final monthlyInfo = _getPlanInfo(
      monthlyStandalone ?? proProduct,
      'musclemirror-month-v2',
    );

    final yearlyProProduct = yearlyStandalone ?? proProduct;
    final monthlyProProduct = monthlyStandalone ?? proProduct;

    final ticketProduct = _getProduct(ProductIds.ticket);
    final hasAnyProduct = proProduct != null || ticketProduct != null;

    if (hasAnyProduct) {
      debugPrint(
        '[SubscriptionPage] Products found: '
        'pro=${proProduct?.id}, '
        'yearly=${yearlyStandalone?.id}, '
        'monthly=${monthlyStandalone?.id}, '
        'ticket=${ticketProduct?.id}',
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('プラン・チケット購入')),
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
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 20,
                    ),
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
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(
                    100,
                  ),
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
                        'Store Debug Info:\n'
                        'Queried: ${ProductIds.all.join(", ")}\n'
                        'Found (${_billingService.products.length}): ${_billingService.products.map((p) => "${p.id}(${p.price})").join(", ")}\n'
                        'Not Found: ${_billingService.notFoundIDs.join(", ")}',
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
              // Debug Info (Found products)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ExpansionTile(
                  title: const Text(
                    'デバッグ情報 (ストア接続状態)',
                    style: TextStyle(fontSize: 12),
                  ),
                  dense: true,
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Found IDs: ${_billingService.products.map((p) => p.id).join(", ")}\n'
                        'Not Found: ${_billingService.notFoundIDs.isEmpty ? "none" : _billingService.notFoundIDs.join(", ")}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 1. Monthly Pro Subscription
              if (monthlyProProduct != null) ...[
                Builder(
                  builder: (context) {
                    final isOwned =
                        _billingService.hasActiveSubscription &&
                        _billingService.meStatus?.planTier == 'pro' &&
                        _billingService.meStatus?.effectivePlan !=
                            ProductIds.proYearly;

                    return _SubscriptionCard(
                      title: '月額プラン',
                      price: monthlyInfo.price ?? monthlyProProduct.price,
                      description: '毎月自動更新・すべての機能が使い放題',
                      isLoading: _isLoading,
                      isOwned: isOwned,
                      onTap: isOwned
                          ? null
                          : () => _doPurchase(
                              () => _billingService.purchaseBasePlan(
                                monthlyProProduct,
                                offerToken: monthlyInfo.offerToken,
                              ),
                            ),
                    );
                  },
                ),

                const SizedBox(height: 12),

                // 2. Yearly Pro Subscription (recommended)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Builder(
                      builder: (context) {
                        final isOwned =
                            _billingService.hasActiveSubscription &&
                            _billingService.meStatus?.effectivePlan ==
                                ProductIds.proYearly;

                        return _SubscriptionCard(
                          title: '年額プラン',
                          price:
                              yearlyInfo.price ??
                              yearlyProProduct?.price ??
                              '¥4,800',
                          description: '毎年自動更新（2ヶ月分お得！）',
                          isPopular: true,
                          isLoading: _isLoading,
                          isOwned: isOwned,
                          onTap: isOwned
                              ? null
                              : (yearlyProProduct != null
                                    ? () => _doPurchase(
                                        () => _billingService.purchaseBasePlan(
                                          yearlyProProduct,
                                          offerToken: yearlyInfo.offerToken,
                                        ),
                                      )
                                    : null),
                        );
                      },
                    ),
                    Positioned(
                      top: -10,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
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
              if (ticketProduct != null &&
                  !_billingService.hasActiveSubscription)
                _SubscriptionCard(
                  title: '1回分チケット',
                  price: ticketProduct.price,
                  description: '1回分の判定チケット',
                  icon: Icons.confirmation_number,
                  isLoading: _isLoading,
                  isOwned: _billingService.ticketCount > 0,
                  onTap: _purchaseTicket,
                ),
            ],

            const SizedBox(height: 24),

            // Restore purchases
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      setState(() => _isLoading = true);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await _billingService.restorePurchases();
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(content: Text('購入の復元プロセスを開始しました')),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(content: Text('復元中にエラーが発生しました: $e')),
                        );
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
          Icon(icon, color: theme.colorScheme.primary, size: 24),
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
  final bool isOwned;
  final IconData? icon;
  final VoidCallback? onTap;

  const _SubscriptionCard({
    required this.title,
    required this.price,
    required this.description,
    this.isPopular = false,
    this.isLoading = false,
    this.isOwned = false,
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
              else if (isOwned)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '契約中',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.arrow_forward_ios,
                  color: isOwned ? Colors.grey : theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
