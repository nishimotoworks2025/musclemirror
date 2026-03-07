import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'billing_api_client.dart';
import 'auth_service.dart';
import '../models/me_status.dart';

/// Product IDs for Google Play
class ProductIds {
  // Subscription (定期購入) - アイテムID
  static const String pro = 'musclemirror_pro';

  // One-time purchase (アプリ内アイテム) - 1回分チケット
  static const String ticket = 'musclemirror_once';

  // All product IDs to query
  static const Set<String> all = {pro, ticket};

  // Subscription product IDs (for Pro status check)
  static const Set<String> subscriptions = {pro};
}

// Keep backward compatibility alias
typedef SubscriptionProductIds = ProductIds;

/// Service for handling in-app purchases and subscriptions.
/// Ported from TrueSkin architecture with server-side verification.
class BillingService {
  static final BillingService _instance = BillingService._internal();
  factory BillingService() => _instance;
  BillingService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final BillingApiClient _apiClient = BillingApiClient();
  final AuthService _authService = AuthService();
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Timer? _expiryTimer;

  List<ProductDetails> _products = [];
  List<ProductDetails> get products => _products;

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Debug info for troubleshooting
  String _debugInfo = '';
  String get debugInfo => _debugInfo;
  List<String> _notFoundIDs = [];
  List<String> get notFoundIDs => _notFoundIDs;

  // Pro status notifier for reactive UI updates
  final _isProNotifier = ValueNotifier<bool>(false);
  ValueNotifier<bool> get isProNotifier => _isProNotifier;
  bool get isPro => _isProNotifier.value;

  // Auto-renewing status (like TrueSkin)
  bool _isProAutoRenewing = false;
  bool get isProAutoRenewing => _isProAutoRenewing;

  // Track if we found any active subscription during restore
  bool _hasActiveSubscription = false;
  bool get hasActiveSubscription =>
      _meStatus?.hasProEntitlement ?? _hasActiveSubscription;

  // Server-side status
  MeStatus? _meStatus;
  MeStatus? get meStatus => _meStatus;

  String get effectivePlan =>
      _meStatus?.resolvedEffectivePlan ?? (isPro ? 'pro' : 'free');

  void _applyEntitlementState() {
    _hasActiveSubscription = _meStatus?.hasProEntitlement ?? false;
    _isProNotifier.value = _hasActiveSubscription || _ticketCount > 0;
    _scheduleExpiryTimer();
  }

  void _scheduleExpiryTimer() {
    _expiryTimer?.cancel();

    final expiry = _meStatus?.expiresAtDate;
    if (expiry == null) {
      return;
    }

    final remaining = expiry.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      return;
    }

    _expiryTimer = Timer(remaining, _applyEntitlementAfterExpiry);
  }

  void _applyEntitlementAfterExpiry() {
    _hasActiveSubscription = _meStatus?.hasProEntitlement ?? false;
    _isProNotifier.value = _hasActiveSubscription || _ticketCount > 0;

    if (_authService.isAuthenticated) {
      unawaited(syncWithServer());
    }
  }

  /// Synchronize authoritative subscription status with the server.
  Future<void> syncWithServer() async {
    if (!_authService.isAuthenticated) return;

    try {
      debugPrint('BillingService: Syncing with server...');
      _meStatus = await _apiClient.fetchMe();

      // Update Pro status from server info
      if (_meStatus != null) {
        _applyEntitlementState();
        debugPrint(
          'BillingService: Server sync complete. '
          'Plan: ${_meStatus!.resolvedEffectivePlan}, '
          'Status: ${_meStatus!.planStatus}, '
          'Expired: ${_meStatus!.isExpired}',
        );
      }
    } catch (e) {
      debugPrint('BillingService: Server sync failed: $e');
    }
  }

  // Local persistent ticket count
  static const String _ticketCountKey = 'musclemirror_ticket_count';
  int _ticketCount = 0;
  int get ticketCount => _ticketCount;

  // Callback for purchase completion
  void Function(PurchaseDetails)? onPurchaseCompleted;
  VoidCallback? onPurchaseSuccess;
  ValueChanged<String>? onPurchaseError;

  /// Initialize the billing service.
  /// This initializes the BillingClient, loads products, and auto-restores purchases.
  Future<void> initialize({bool forceReload = false}) async {
    if (_isInitialized && !forceReload) return;
    _debugInfo = 'Initializing...';

    try {
      // Check if in-app purchases are available
      _isAvailable = await _inAppPurchase.isAvailable();

      if (!_isAvailable) {
        _debugInfo = 'ERROR: In-app purchases not available on this device';
        debugPrint('BillingService: In-app purchases not available');
        return;
      }

      debugPrint('BillingService: In-app purchases available');

      // Load persistent ticket count
      final prefs = await SharedPreferences.getInstance();
      _ticketCount = prefs.getInt(_ticketCountKey) ?? 0;
      debugPrint('BillingService: Loaded local ticket count: $_ticketCount');

      // Start listening for purchase updates
      _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: (error) {
          debugPrint('BillingService: Purchase stream error: $error');
        },
      );

      // Query available products
      await _loadProducts();

      // Build debug info
      final buf = StringBuffer();
      buf.writeln('Available: $_isAvailable');
      buf.writeln('Products found: ${_products.length}');
      buf.writeln('Queried IDs: ${SubscriptionProductIds.all}');
      if (_notFoundIDs.isNotEmpty) {
        buf.writeln('NOT FOUND: $_notFoundIDs');
      }
      for (final product in _products) {
        buf.writeln('  ✓ ${product.id}: ${product.price}');
        debugPrint(
          '  - [ID: ${product.id}] Title: ${product.title}, Price: ${product.price}',
        );
      }
      _debugInfo = buf.toString();

      // AUTHORITATIVE SYNC: Fetch status from server if logged in
      if (_authService.isAuthenticated) {
        await syncWithServer();
      }

      _isInitialized = true;

      debugPrint('BillingService: Initialized successfully');
    } catch (e) {
      _debugInfo = 'INIT ERROR: $e';
      debugPrint('BillingService: Initialization error: $e');
    }
  }

  /// Load subscription products from the store
  Future<void> _loadProducts() async {
    try {
      debugPrint(
        'BillingService: Querying product details for ${SubscriptionProductIds.all}...',
      );
      final ProductDetailsResponse response = await _inAppPurchase
          .queryProductDetails(SubscriptionProductIds.all);

      _notFoundIDs = response.notFoundIDs.toList();
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
          'BillingService: WARNING - Products not found: ${response.notFoundIDs}',
        );
      }

      _products = response.productDetails;
      debugPrint('BillingService: Loaded ${_products.length} products');

      // Build debug info
      final buf = StringBuffer();
      buf.writeln('Available: $_isAvailable');
      buf.writeln('Products found: ${_products.length}');
      buf.writeln('Queried IDs: ${SubscriptionProductIds.all}');
      if (_notFoundIDs.isNotEmpty) {
        buf.writeln('NOT FOUND: $_notFoundIDs');
      }
      for (final product in _products) {
        buf.writeln('  ✓ ${product.id}: ${product.price}');
        debugPrint(
          '  - [ID: ${product.id}] Title: ${product.title}, Price: ${product.price}',
        );
      }
      _debugInfo = buf.toString();
    } catch (e) {
      _debugInfo = 'LOAD ERROR: $e';
      debugPrint('BillingService: CRITICAL ERROR loading products: $e');
    }
  }

  /// Handle purchase updates from the purchase stream
  void _handlePurchaseUpdates(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      debugPrint(
        'BillingService: Purchase update - ${purchase.productID}: ${purchase.status}',
      );

      switch (purchase.status) {
        case PurchaseStatus.pending:
          // Show loading indicator
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Verify and deliver the purchase
          _verifyAndDeliverPurchase(purchase);
          break;
        case PurchaseStatus.error:
          // Handle error
          debugPrint('BillingService: Purchase error: ${purchase.error}');
          onPurchaseError?.call('Store Error: ${purchase.error?.message}');
          break;
        case PurchaseStatus.canceled:
          // User canceled
          break;
      }

      // Complete the purchase if needed
      if (purchase.pendingCompletePurchase) {
        _inAppPurchase.completePurchase(purchase);
      }
    }
  }

  /// Verify and deliver a purchase (like TrueSkin _onPurchaseUpdate)
  Future<void> _verifyAndDeliverPurchase(PurchaseDetails purchase) async {
    debugPrint('BillingService: Verifying purchase: ${purchase.productID}');
    debugPrint('  - Purchase ID: ${purchase.purchaseID}');
    debugPrint('  - Status: ${purchase.status}');

    // Track auto-renewing status for subscription products (like TrueSkin line 276-279)
    if (ProductIds.subscriptions.contains(purchase.productID) &&
        purchase is GooglePlayPurchaseDetails) {
      _isProAutoRenewing = purchase.billingClientPurchase.isAutoRenewing;
      debugPrint(
        'BillingService: Updated isProAutoRenewing: $_isProAutoRenewing',
      );
    }

    // Update Pro status for subscription products AND the one-time ticket
    // This allows the user to immediately perform Pro features after buying the ticket
    if (ProductIds.subscriptions.contains(purchase.productID) ||
        purchase.productID == ProductIds.ticket) {
      if (ProductIds.subscriptions.contains(purchase.productID)) {
        _hasActiveSubscription =
            true; // Only subs count as strictly "Active Subscription" forever
      }
      _isProNotifier.value = true;
      debugPrint(
        'BillingService: Pro status activated for ${purchase.productID}',
      );
    }

    // Handle ticket purchase
    if (purchase.productID == ProductIds.ticket &&
        purchase.status == PurchaseStatus.purchased) {
      debugPrint('BillingService: Ticket purchased');
      // Increment local persistent ticket count
      final prefs = await SharedPreferences.getInstance();
      _ticketCount = (prefs.getInt(_ticketCountKey) ?? 0) + 1;
      await prefs.setInt(_ticketCountKey, _ticketCount);
      debugPrint('BillingService: Ticket count increased to $_ticketCount');
    }

    // Register purchase with server (like TrueSkin line 288)
    if (_authService.isAuthenticated) {
      final purchaseToken = purchase.verificationData.serverVerificationData;
      try {
        await _apiClient.registerPurchase(purchase.productID, purchaseToken);
        debugPrint('BillingService: Server registration success');
      } catch (e) {
        // Don't block the purchase flow if server registration fails
        // The nightly sync will catch up
        final errorStr = e.toString();
        if (errorStr.contains('Authorization required') ||
            errorStr.contains('ログインが必要')) {
          debugPrint(
            'BillingService: Skipping server registration for unauthenticated user',
          );
        } else {
          debugPrint(
            'BillingService: Failed to register purchase on server: $e',
          );
        }
      }
    } else {
      debugPrint(
        'BillingService: Skipping server registration (not authenticated)',
      );
    }

    // Notify listeners of completed purchase
    onPurchaseCompleted?.call(purchase);

    // Only call success callback for new purchases (not restores)
    if (purchase.status == PurchaseStatus.purchased) {
      onPurchaseSuccess?.call();
    }
  }

  /// Purchase a subscription product (non-consumable)
  Future<bool> purchaseSubscription(String productId) async {
    final product = _products.firstWhere(
      (p) => p.id == productId,
      orElse: () => throw Exception('Product not found: $productId'),
    );
    return _purchase(product, consumable: false);
  }

  /// Purchase a specific base plan (e.g. for Android Subscriptions with multiple base plans)
  Future<bool> purchaseBasePlan(ProductDetails product) async {
    return _purchase(product, consumable: false);
  }

  /// Purchase a consumable product (one-time ticket)
  Future<bool> purchaseConsumable(String productId) async {
    final product = _products.firstWhere(
      (p) => p.id == productId,
      orElse: () => throw Exception('Product not found: $productId'),
    );
    return _purchase(product, consumable: true);
  }

  /// Internal purchase method
  Future<bool> _purchase(
    ProductDetails product, {
    required bool consumable,
  }) async {
    if (!_isAvailable) {
      debugPrint('BillingService: Cannot purchase - not available');
      return false;
    }

    final purchaseParam = PurchaseParam(productDetails: product);

    try {
      if (consumable) {
        return await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
      } else {
        return await _inAppPurchase.buyNonConsumable(
          purchaseParam: purchaseParam,
        );
      }
    } catch (e) {
      debugPrint('BillingService: Purchase error: $e');
      return false;
    }
  }

  /// Restore previous purchases
  Future<void> restorePurchases() async {
    if (!_isAvailable) return;
    _hasActiveSubscription = false;
    await _inAppPurchase.restorePurchases();

    // Authoritative Sync after restore
    if (_authService.isAuthenticated) {
      await syncWithServer();
    }

    // Re-check ticket status after restore
    await Future.delayed(const Duration(seconds: 2));
    if (!hasActiveSubscription && _ticketCount == 0) {
      _isProNotifier.value = false;
    } else if (_ticketCount > 0) {
      _isProNotifier.value = true;
    }
  }

  /// Consume one ticket
  Future<void> consumeTicket() async {
    if (_ticketCount > 0) {
      _ticketCount--;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_ticketCountKey, _ticketCount);
      debugPrint('BillingService: Consumed ticket. Remaining: $_ticketCount');

      // If no tickets left and no active subscription, remove Pro status
      if (_ticketCount == 0 && !hasActiveSubscription) {
        _isProNotifier.value = false;
        debugPrint('BillingService: Tickets depleted. Demoted to Free.');
      }
    }
  }

  /// Dispose the service
  void dispose() {
    _expiryTimer?.cancel();
    _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _isInitialized = false;
  }
}
