import 'dart:io';
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
  static const String proYearly = 'musclemirror-year';
  static const String proMonthlyV2 = 'musclemirror-month-v2';

  // One-time purchase (アプリ内アイテム) - 1回分チケット
  static const String ticket = 'musclemirror_once';

  // All product IDs to query
  static const Set<String> all = {pro, proYearly, proMonthlyV2, ticket};

  // Subscription product IDs (for Pro status check)
  static const Set<String> subscriptions = {pro, proYearly, proMonthlyV2};
}

// Keep backward compatibility alias
typedef SubscriptionProductIds = ProductIds;

/// Service for handling in-app purchases and subscriptions.
/// Ported from TrueSkin architecture with server-side verification.
class BillingService {
  static const Duration _storeInitTimeout = Duration(seconds: 8);
  static const Duration _serverSyncTimeout = Duration(seconds: 8);
  static final BillingService _instance = BillingService._internal();
  factory BillingService() => _instance;
  BillingService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final BillingApiClient _apiClient = BillingApiClient();
  final AuthService _authService = AuthService();
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Timer? _expiryTimer;
  Future<void>? _initializationFuture;
  bool _isRecoveringFromStore = false;
  DateTime? _lastStoreRecoveryAt;

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
  final _entitlementVersionNotifier = ValueNotifier<int>(0);
  ValueNotifier<int> get entitlementVersionNotifier =>
      _entitlementVersionNotifier;

  // Auto-renewing status (like TrueSkin)
  bool _isProAutoRenewing = false;
  bool get isProAutoRenewing => _isProAutoRenewing;

  static const Set<String> _subscriptionPlanStatuses = {
    'active',
    'trialing',
    'pending',
    'cancelled',
    'grace_period',
    'in_grace_period',
    'on_hold',
    'paused',
  };

  /// Whether the user has a recurring Pro subscription (not a one-time ticket).
  bool get hasActiveSubscription => _hasServerSubscriptionStatus();
  bool get hasTicketEntitlement => _ticketCount > 0;
  bool get hasProAccess => hasActiveSubscription || hasTicketEntitlement;

  bool _hasServerSubscriptionStatus() {
    final status = _meStatus;
    if (status == null) {
      debugPrint(
        'BillingService: _hasServerSubscriptionStatus check - status is null',
      );
      return false;
    }
    if (!status.hasProEntitlement) {
      debugPrint(
        'BillingService: _hasServerSubscriptionStatus check - hasProEntitlement is false',
      );
      return false;
    }
    final isRecurring = status.effectivePlan != ProductIds.ticket;
    final statusOk = _subscriptionPlanStatuses.contains(status.planStatus);
    debugPrint(
      'BillingService: _hasServerSubscriptionStatus check - isRecurring: $isRecurring, planStatus: ${status.planStatus}, statusOk: $statusOk',
    );
    return isRecurring && statusOk;
  }

  // Server-side status
  MeStatus? _meStatus;
  MeStatus? get meStatus => _meStatus;

  String _describeMeStatus(MeStatus? status) {
    if (status == null) return 'null';
    return 'planTier=${status.planTier}, '
        'effectivePlan=${status.effectivePlan}, '
        'resolvedPlan=${status.resolvedEffectivePlan}, '
        'planStatus=${status.planStatus}, '
        'expiresAt=${status.expiresAt}, '
        'isExpired=${status.isExpired}, '
        'hasProEntitlement=${status.hasProEntitlement}';
  }

  String get effectivePlan =>
      _meStatus?.resolvedEffectivePlan ?? (isPro ? 'pro' : 'free');

  void _applyEntitlementState() {
    final oldPro = _isProNotifier.value;
    _isProNotifier.value = hasActiveSubscription;
    _entitlementVersionNotifier.value++;
    debugPrint(
      'BillingService: Pro state applied - '
      'isPro=${_isProNotifier.value} (was $oldPro), '
      'hasActiveSub=$hasActiveSubscription, '
      'hasTicket=$hasTicketEntitlement, '
      'status={${_describeMeStatus(_meStatus)}}',
    );
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

  Future<void> _applyEntitlementAfterExpiry() async {
    // Re-sync with server first to get the authoritative expiry status
    if (_authService.isAuthenticated) {
      await syncWithServer();
    } else {
      _isProNotifier.value = false;
    }
  }

  bool _isRegisteringPurchase = false;

  bool get _canAttemptStoreRecovery {
    if (!Platform.isAndroid || !_authService.isAuthenticated) {
      return false;
    }
    if (_isRegisteringPurchase || _isRecoveringFromStore) {
      return false;
    }
    final lastAttempt = _lastStoreRecoveryAt;
    if (lastAttempt == null) {
      return true;
    }
    return DateTime.now().difference(lastAttempt) > const Duration(minutes: 2);
  }

  Future<void> _attemptStoreRecovery() async {
    if (!_canAttemptStoreRecovery) {
      return;
    }

    _isRecoveringFromStore = true;
    _lastStoreRecoveryAt = DateTime.now();

    try {
      debugPrint(
        'BillingService: Attempting Play Store recovery because server reported no active subscription.',
      );
      await _inAppPurchase.restorePurchases();
      await Future.delayed(const Duration(seconds: 2));
      _meStatus = await _apiClient.fetchMe();
      debugPrint(
        'BillingService: Recovery /me synced -> {${_describeMeStatus(_meStatus)}}',
      );
      _applyEntitlementState();
    } catch (e) {
      debugPrint('BillingService: Store recovery failed: $e');
    } finally {
      _isRecoveringFromStore = false;
    }
  }

  /// Synchronize authoritative subscription status with the server.
  Future<void> syncWithServer() async {
    if (!_authService.isAuthenticated) {
      await _authService.restoreSession();
    }

    if (!_authService.isAuthenticated) {
      _meStatus = null;
      _applyEntitlementState();
      return;
    }

    if (_isRegisteringPurchase) {
      debugPrint(
        'BillingService: Skipping syncWithServer because a purchase is currently being registered.',
      );
      return;
    }

    try {
      debugPrint('BillingService: Syncing with server...');
      _meStatus = await _apiClient.fetchMe().timeout(_serverSyncTimeout);
      debugPrint(
        'BillingService: /me synced -> {${_describeMeStatus(_meStatus)}}',
      );
      _applyEntitlementState();

      if (_meStatus != null) {
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
  // Set of purchaseIDs that have already been granted as tickets (for deduplication)
  static const String _processedTicketIdsKey =
      'musclemirror_processed_ticket_ids';
  int _ticketCount = 0;
  int get ticketCount => _ticketCount;
  Set<String> _processedTicketIds = {};
  final Set<String> _processingTicketIds = {};

  // Callback for purchase completion
  void Function(PurchaseDetails)? onPurchaseCompleted;
  VoidCallback? onPurchaseSuccess;
  ValueChanged<String>? onPurchaseError;

  Map<String, Object?> get debugSnapshot => {
    'initialized': _isInitialized,
    'available': _isAvailable,
    'isPro': _isProNotifier.value,
    'hasActiveSubscription': hasActiveSubscription,
    'hasTicketEntitlement': hasTicketEntitlement,
    'ticketCount': _ticketCount,
    'processedTicketIds': _processedTicketIds.length,
    'processingTicketIds': _processingTicketIds.length,
    'effectivePlan': effectivePlan,
    'planStatus': _meStatus?.planStatus,
    'expiresAt': _meStatus?.expiresAt,
  };

  /// Initialize the billing service.
  /// This initializes the BillingClient, loads products, and auto-restores purchases.
  Future<void> initialize({bool forceReload = false}) async {
    if (_isInitialized && !forceReload) return;
    if (_initializationFuture != null && !forceReload) {
      await _initializationFuture;
      return;
    }

    _initializationFuture = _initializeInternal();
    try {
      await _initializationFuture;
    } finally {
      _initializationFuture = null;
    }
  }

  Future<void> _initializeInternal() async {
    _debugInfo = 'Initializing...';

    try {
      // Check if in-app purchases are available
      _isAvailable = await _inAppPurchase.isAvailable().timeout(
        _storeInitTimeout,
        onTimeout: () => false,
      );

      if (!_isAvailable) {
        _debugInfo = 'ERROR: In-app purchases not available on this device';
        debugPrint('BillingService: In-app purchases not available');
        return;
      }

      debugPrint('BillingService: In-app purchases available');

      // Load persistent ticket count
      final prefs = await SharedPreferences.getInstance();
      _ticketCount = prefs.getInt(_ticketCountKey) ?? 0;
      // Load processed ticket IDs for deduplication
      _processedTicketIds = Set<String>.from(
        prefs.getStringList(_processedTicketIdsKey) ?? [],
      );

      // If local ticket count exceeds the number of distinct granted ticket tokens,
      // the count was duplicated by restore/replay. Clamp it back to a safe value.
      if (_processedTicketIds.isNotEmpty &&
          _ticketCount > _processedTicketIds.length) {
        _ticketCount = _processedTicketIds.length;
        await prefs.setInt(_ticketCountKey, _ticketCount);
        debugPrint(
          'BillingService: Normalized duplicated ticket count to $_ticketCount',
        );
      }

      debugPrint(
        'BillingService: Loaded local ticket count: $_ticketCount, processed IDs: ${_processedTicketIds.length}',
      );

      // Start listening for purchase updates
      await _purchaseSubscription?.cancel();
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
          .queryProductDetails(SubscriptionProductIds.all)
          .timeout(
            _storeInitTimeout,
            onTimeout: () => ProductDetailsResponse(
              productDetails: const [],
              notFoundIDs: SubscriptionProductIds.all.toList(),
              error: null,
            ),
          );

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
  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
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
          // Process sequentially so the same purchase cannot grant a ticket twice.
          await _verifyAndDeliverPurchase(purchase);
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

      // EXHAUSTIVE LOGGING FOR EVERY UPDATE
      debugPrint(
        '   - Full Update: ID=${purchase.purchaseID}, Product=${purchase.productID}, Status=${purchase.status}, PendingComplete=${purchase.pendingCompletePurchase}',
      );
      debugPrint(
        '   - Update Token (Partial): ${purchase.verificationData.serverVerificationData.length > 20 ? purchase.verificationData.serverVerificationData.substring(0, 20) : purchase.verificationData.serverVerificationData}...',
      );
      if (purchase.error != null) {
        debugPrint(
          '   - Update Error: ${purchase.error!.code}: ${purchase.error!.message}',
        );
      }

      // AGGRESSIVE "ZOMBIE CLEAN" FOR ANDROID TICKETS
      // Try to consume ANY ticket update on Android, regardless of status (unless it's an error)
      // This is to clear items that are "Owned" but "Unconsumed" in the store.
      if (Platform.isAndroid &&
          purchase.productID == ProductIds.ticket &&
          purchase.status != PurchaseStatus.error) {
        try {
          final androidAddition = _inAppPurchase
              .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
          await androidAddition.consumePurchase(purchase);
          debugPrint(
            'BillingService: AGGRESSIVE-CLEAN success for ticket ${purchase.purchaseID}',
          );
        } catch (e) {
          // Expected to fail if already consumed or not consumable.
          debugPrint('BillingService: AGGRESSIVE-CLEAN note: $e');
        }
      }

      // Complete the purchase if needed
      if (purchase.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchase);
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

    // Handle ticket purchase — with deduplication to avoid double-counting on restore
    if (purchase.productID == ProductIds.ticket &&
        (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored)) {
      // Use purchaseToken (serverVerificationData) for robust deduplication as OrderID/PurchaseID can be empty or change
      final token = purchase.verificationData.serverVerificationData;
      final ticketKey = token.isNotEmpty
          ? token
          : (purchase.purchaseID ?? purchase.productID);

      if (_processingTicketIds.contains(ticketKey)) {
        debugPrint(
          'BillingService: Ticket is already being processed - skipping duplicate update',
        );
      } else if (token.isNotEmpty && _processedTicketIds.contains(token)) {
        debugPrint(
          'BillingService: Ticket token already processed — skipping grant',
        );
      } else {
        _processingTicketIds.add(ticketKey);
        try {
          debugPrint(
            'BillingService: Granting ticket for token: ${token.length > 20 ? token.substring(0, 20) : token}...',
          );
          final prefs = await SharedPreferences.getInstance();
          _ticketCount = (prefs.getInt(_ticketCountKey) ?? 0) + 1;
          await prefs.setInt(_ticketCountKey, _ticketCount);
          if (token.isNotEmpty) {
            _processedTicketIds.add(token);
            await prefs.setStringList(
              _processedTicketIdsKey,
              _processedTicketIds.toList(),
            );
          }
          _applyEntitlementState();
          debugPrint('BillingService: Ticket count increased to $_ticketCount');
        } finally {
          _processingTicketIds.remove(ticketKey);
        }
      }

      // Note: We used to have proactive consumption here, but now it's handled
      // globally in _handlePurchaseUpdates for ALL ticket updates (even processed ones).
    }

    // Register purchase with server (like TrueSkin line 288)
    if (_authService.isAuthenticated &&
        ProductIds.subscriptions.contains(purchase.productID)) {
      final purchaseToken = purchase.verificationData.serverVerificationData;
      try {
        _isRegisteringPurchase = true;
        final jsonResult = await _apiClient.registerPurchase(
          purchase.productID,
          purchaseToken,
        );
        debugPrint(
          'BillingService: Server registration success -> $jsonResult',
        );

        // Immediately update _meStatus with the registration result to reflect server confirmation
        _meStatus = MeStatus.fromJson(jsonResult);
        debugPrint(
          'BillingService: Registration mapped to status -> {${_describeMeStatus(_meStatus)}}',
        );
        _applyEntitlementState(); // This will apply the new state safely

        // Safety Delay: Wait 2 seconds for DynamoDB to propagate before final sync
        debugPrint('BillingService: Waiting 2s for DB propagation...');
        await Future.delayed(const Duration(seconds: 2));

        // After successful registration, explicitly sync to get the full /me status
        _isRegisteringPurchase = false;
        await syncWithServer();
      } catch (e) {
        _isRegisteringPurchase = false;
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
        'BillingService: Skipping server registration '
        '(${_authService.isAuthenticated ? "ticket purchase" : "not authenticated"})',
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
    if (!_authService.isAuthenticated) {
      debugPrint(
        'BillingService: Subscription purchase rejected - authentication required',
      );
      return false;
    }
    final product = _products.firstWhere(
      (p) => p.id == productId,
      orElse: () => throw Exception('Product not found: $productId'),
    );
    return _purchase(product, consumable: false);
  }

  /// Purchase a specific base plan (e.g. for Android Subscriptions with multiple base plans)
  Future<bool> purchaseBasePlan(
    ProductDetails product, {
    String? offerToken,
  }) async {
    if (!_authService.isAuthenticated) {
      debugPrint(
        'BillingService: Base plan purchase rejected - authentication required',
      );
      return false;
    }
    return _purchase(product, consumable: false, offerToken: offerToken);
  }

  /// Purchase a consumable product (one-time ticket)
  Future<bool> purchaseConsumable(String productId) async {
    if (!_authService.isAuthenticated) {
      debugPrint(
        'BillingService: Ticket purchase rejected - authentication required',
      );
      return false;
    }
    if (hasActiveSubscription) {
      debugPrint(
        'BillingService: Ticket purchase rejected - active subscription already present',
      );
      return false;
    }
    final product = _products.firstWhere(
      (p) => p.id == productId,
      orElse: () => throw Exception('Product not found: $productId'),
    );
    debugPrint('BillingService: Starting purchase for consumable: $productId');
    // Tickets are consumable.
    return _purchase(product, consumable: true);
  }

  /// Internal purchase method
  Future<bool> _purchase(
    ProductDetails product, {
    required bool consumable,
    String? offerToken,
  }) async {
    if (!_isAvailable) {
      debugPrint('BillingService: Cannot purchase - not available');
      return false;
    }

    PurchaseParam purchaseParam;
    if (Platform.isAndroid && offerToken != null) {
      purchaseParam = GooglePlayPurchaseParam(
        productDetails: product,
        applicationUserName: null,
        changeSubscriptionParam: null,
        offerToken: offerToken,
      );
    } else {
      purchaseParam = PurchaseParam(productDetails: product);
    }

    try {
      if (consumable) {
        return await _inAppPurchase.buyConsumable(
          purchaseParam: purchaseParam,
          autoConsume: true,
        ); // Enable autoConsume on Android too for better reliability
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
    debugPrint('BillingService: Restoring purchases...');
    await _inAppPurchase.restorePurchases();

    // Re-check for any stuck tickets on Android and try to consume them
    if (Platform.isAndroid) {
      debugPrint(
        'BillingService: Android Force-Cleanup - Attempting to consume all past tickets',
      );
      // On Android, restorePurchases() will populate the purchase stream with previous purchases.
      // Our aggressive _handlePurchaseUpdates will handle the consumption of any that are still owned.
    }

    // Authoritative Sync after restore
    if (_authService.isAuthenticated) {
      await syncWithServer();
    }

    debugPrint(
      'BillingService: Restore cycle complete. Final ticket count: $_ticketCount',
    );
  }

  /// Consume one ticket
  Future<void> consumeTicket() async {
    if (_ticketCount > 0) {
      _ticketCount--;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_ticketCountKey, _ticketCount);
      _applyEntitlementState();
      debugPrint('BillingService: Consumed ticket. Remaining: $_ticketCount');
    }
  }

  Future<void> clearLocalEntitlements() async {
    final prefs = await SharedPreferences.getInstance();
    _ticketCount = 0;
    _processedTicketIds = {};
    _processingTicketIds.clear();
    _meStatus = null;
    _isProNotifier.value = false;

    await prefs.remove(_ticketCountKey);
    await prefs.remove(_processedTicketIdsKey);
    _applyEntitlementState();
  }

  /// Dispose the service
  void dispose() {
    _expiryTimer?.cancel();
    _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _isInitialized = false;
  }
}
