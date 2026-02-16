import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubscriptionState {
  final bool loading;
  final bool isPremium;
  final bool needsRefresh;
  final DateTime? lastValidatedAt;
  final String source;
  final String? error;
  final String? activeProductIdentifier;
  final DateTime? entitlementExpirationDate;
  final bool? entitlementWillRenew;
  final DateTime? latestPurchaseDate;
  final DateTime? unsubscribeDetectedAt;
  final DateTime? billingIssueDetectedAt;

  const SubscriptionState({
    required this.loading,
    required this.isPremium,
    required this.needsRefresh,
    required this.source,
    this.lastValidatedAt,
    this.error,
    this.activeProductIdentifier,
    this.entitlementExpirationDate,
    this.entitlementWillRenew,
    this.latestPurchaseDate,
    this.unsubscribeDetectedAt,
    this.billingIssueDetectedAt,
  });

  factory SubscriptionState.initial() {
    return const SubscriptionState(
      loading: true,
      isPremium: false,
      needsRefresh: true,
      source: 'init',
    );
  }

  SubscriptionState copyWith({
    bool? loading,
    bool? isPremium,
    bool? needsRefresh,
    DateTime? lastValidatedAt,
    bool clearLastValidatedAt = false,
    String? activeProductIdentifier,
    DateTime? entitlementExpirationDate,
    bool? entitlementWillRenew,
    DateTime? latestPurchaseDate,
    DateTime? unsubscribeDetectedAt,
    DateTime? billingIssueDetectedAt,
    bool clearEntitlementDetails = false,
    String? source,
    String? error,
    bool clearError = false,
  }) {
    return SubscriptionState(
      loading: loading ?? this.loading,
      isPremium: isPremium ?? this.isPremium,
      needsRefresh: needsRefresh ?? this.needsRefresh,
      lastValidatedAt: clearLastValidatedAt
          ? null
          : (lastValidatedAt ?? this.lastValidatedAt),
      activeProductIdentifier: clearEntitlementDetails
          ? null
          : (activeProductIdentifier ?? this.activeProductIdentifier),
      entitlementExpirationDate: clearEntitlementDetails
          ? null
          : (entitlementExpirationDate ?? this.entitlementExpirationDate),
      entitlementWillRenew: clearEntitlementDetails
          ? null
          : (entitlementWillRenew ?? this.entitlementWillRenew),
      latestPurchaseDate: clearEntitlementDetails
          ? null
          : (latestPurchaseDate ?? this.latestPurchaseDate),
      unsubscribeDetectedAt: clearEntitlementDetails
          ? null
          : (unsubscribeDetectedAt ?? this.unsubscribeDetectedAt),
      billingIssueDetectedAt: clearEntitlementDetails
          ? null
          : (billingIssueDetectedAt ?? this.billingIssueDetectedAt),
      source: source ?? this.source,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

enum PurchaseActionResult { success, cancelled, noEntitlement }

class SubscriptionService extends ChangeNotifier {
  SubscriptionService();

  static const String entitlementName = 'pro_access';
  static const Duration offlineGrace = Duration(hours: 24);
  static const bool _forcePro = bool.fromEnvironment(
    'DEV_FORCE_PRO',
    defaultValue: false,
  );
  static const bool _assumeProWithoutRc = bool.fromEnvironment(
    'ASSUME_PRO_WITHOUT_RC',
    defaultValue: false,
  );
  static const String _sharedPublicKey = String.fromEnvironment(
    'RC_PUBLIC_KEY',
    defaultValue: '',
  );
  static const String _androidPublicKey = String.fromEnvironment(
    'RC_ANDROID_PUBLIC_KEY',
    defaultValue: 'goog_nhAxrUCnywYPuRLYTnzyIpoCtxX',
  );
  static const String _iosPublicKey = String.fromEnvironment(
    'RC_IOS_PUBLIC_KEY',
    defaultValue: '',
  );

  static const String _kCachedPremium = 'cached_premium';
  static const String _kCachedValidatedAt = 'cached_premium_validated_at';

  final ValueNotifier<SubscriptionState> state =
      ValueNotifier<SubscriptionState>(SubscriptionState.initial());

  SharedPreferences? _prefs;
  User? _user;
  bool _configured = false;
  String? _activeRcUserId;
  bool _customerInfoListenerAttached = false;

  bool get isPremium => state.value.isPremium;
  // Cloud sync should follow premium state, including assumed-pro dev mode.
  bool get shouldUseCloudSync => isPremium;

  bool get _isDevOverride => _forcePro && kDebugMode;
  bool get _isAssumedProFallback =>
      _assumeProWithoutRc && kDebugMode && !_canUseRevenueCat;

  String get _publicKey {
    final shared = _sharedPublicKey.trim();
    if (Platform.isAndroid) {
      final key = _androidPublicKey.trim();
      return key.isNotEmpty ? key : shared;
    }
    if (Platform.isIOS || Platform.isMacOS) {
      final key = _iosPublicKey.trim();
      return key.isNotEmpty ? key : shared;
    }
    return shared;
  }

  bool get _canUseRevenueCat => _publicKey.trim().isNotEmpty;

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();

    if (_isDevOverride) {
      _setState(
        state.value.copyWith(
          loading: false,
          isPremium: true,
          needsRefresh: false,
          clearEntitlementDetails: true,
          source: 'dev_override',
          clearError: true,
        ),
      );
      return;
    }

    if (_isAssumedProFallback) {
      _setState(
        state.value.copyWith(
          loading: false,
          isPremium: true,
          needsRefresh: false,
          clearEntitlementDetails: true,
          source: 'assumed_pro_no_revenuecat',
          clearError: true,
        ),
      );
      return;
    }

    final cached = _readCached();
    if (cached != null) {
      _setState(
        state.value.copyWith(
          loading: false,
          isPremium: cached.isPremium,
          needsRefresh: cached.needsRefresh,
          lastValidatedAt: cached.lastValidatedAt,
          source: 'cache',
          clearError: true,
        ),
      );
    } else {
      _setState(
        state.value.copyWith(
          loading: false,
          isPremium: false,
          needsRefresh: true,
          clearEntitlementDetails: true,
          source: _canUseRevenueCat ? 'awaiting_user' : 'missing_keys',
          clearError: true,
        ),
      );
    }
  }

  Future<void> bindAuthenticatedUser(User user) async {
    _user = user;

    if (_isDevOverride) {
      _setState(
        state.value.copyWith(
          loading: false,
          isPremium: true,
          needsRefresh: false,
          clearEntitlementDetails: true,
          source: 'dev_override',
          clearError: true,
        ),
      );
      return;
    }

    if (_isAssumedProFallback) {
      _setState(
        state.value.copyWith(
          loading: false,
          isPremium: true,
          needsRefresh: false,
          clearEntitlementDetails: true,
          source: 'assumed_pro_no_revenuecat',
          clearError: true,
        ),
      );
      return;
    }

    if (!_canUseRevenueCat) {
      _setState(
        state.value.copyWith(
          loading: false,
          isPremium: false,
          needsRefresh: true,
          clearLastValidatedAt: true,
          clearEntitlementDetails: true,
          source: 'missing_keys',
          clearError: true,
        ),
      );
      return;
    }

    _setState(
      state.value.copyWith(
        loading: true,
        source: 'initializing_revenuecat',
        clearError: true,
      ),
    );

    try {
      if (!_configured) {
        await Purchases.setLogLevel(
          kDebugMode ? LogLevel.debug : LogLevel.info,
        );
        final config = PurchasesConfiguration(_publicKey)..appUserID = user.uid;
        await Purchases.configure(config);
        _configured = true;
        _activeRcUserId = user.uid;
      } else if (_activeRcUserId != user.uid) {
        await Purchases.logIn(user.uid);
        _activeRcUserId = user.uid;
      }
      _attachCustomerInfoListenerIfNeeded();
      await refreshEntitlement();
    } catch (e) {
      final cached = _readCached();
      _setState(
        state.value.copyWith(
          loading: false,
          isPremium: cached?.isPremium ?? false,
          needsRefresh: cached?.needsRefresh ?? true,
          lastValidatedAt: cached?.lastValidatedAt,
          clearEntitlementDetails: true,
          source: 'revenuecat_init_failed',
          error: e.toString(),
        ),
      );
    }
  }

  Future<void> unbindUser() async {
    _user = null;
    if (_isDevOverride) return;

    if (_configured) {
      try {
        if (_customerInfoListenerAttached) {
          Purchases.removeCustomerInfoUpdateListener(_onCustomerInfoUpdated);
          _customerInfoListenerAttached = false;
        }
        await Purchases.logOut();
        _activeRcUserId = null;
      } catch (_) {}
    }
    final cached = _readCached();
    _setState(
      state.value.copyWith(
        loading: false,
        isPremium: cached?.isPremium ?? false,
        needsRefresh: cached?.needsRefresh ?? true,
        lastValidatedAt: cached?.lastValidatedAt,
        clearEntitlementDetails: true,
        source: 'signed_out',
        clearError: true,
      ),
    );
  }

  Future<void> refreshEntitlement() async {
    if (_isDevOverride) {
      _setState(
        state.value.copyWith(
          loading: false,
          isPremium: true,
          needsRefresh: false,
          clearEntitlementDetails: true,
          source: 'dev_override',
          clearError: true,
        ),
      );
      return;
    }

    if (_isAssumedProFallback) {
      _setState(
        state.value.copyWith(
          loading: false,
          isPremium: true,
          needsRefresh: false,
          clearEntitlementDetails: true,
          source: 'assumed_pro_no_revenuecat',
          clearError: true,
        ),
      );
      return;
    }

    if (_user == null) {
      _setState(
        state.value.copyWith(
          loading: false,
          isPremium: false,
          needsRefresh: true,
          clearEntitlementDetails: true,
          source: 'no_user',
        ),
      );
      return;
    }

    if (!_canUseRevenueCat) {
      _setState(
        state.value.copyWith(
          loading: false,
          isPremium: false,
          needsRefresh: true,
          clearLastValidatedAt: true,
          clearEntitlementDetails: true,
          source: 'missing_keys',
          clearError: true,
        ),
      );
      return;
    }

    _setState(
      state.value.copyWith(
        loading: true,
        source: 'refreshing',
        clearError: true,
      ),
    );

    try {
      final info = await Purchases.getCustomerInfo();
      await _applyCustomerInfo(info, source: 'revenuecat');
    } catch (e) {
      final cached = _readCached();
      if (cached != null) {
        _setState(
          state.value.copyWith(
            loading: false,
            isPremium: cached.isPremium,
            needsRefresh: cached.needsRefresh,
            lastValidatedAt: cached.lastValidatedAt,
            clearEntitlementDetails: true,
            source: 'cache_after_error',
            error: e.toString(),
          ),
        );
      } else {
        _setState(
          state.value.copyWith(
            loading: false,
            isPremium: false,
            needsRefresh: true,
            clearEntitlementDetails: true,
            source: 'refresh_failed',
            error: e.toString(),
          ),
        );
      }
    }
  }

  Future<Offerings?> fetchOfferings() async {
    if (_isDevOverride || _isAssumedProFallback) return null;
    if (!_canUseRevenueCat || _user == null) return null;
    await _ensureConfiguredForCurrentUser();

    final offerings = await Purchases.getOfferings();
    return offerings;
  }

  Future<PurchaseActionResult> purchasePackage(Package package) async {
    if (_user == null) {
      throw StateError('Authentication required before purchase.');
    }
    if (_isDevOverride || _isAssumedProFallback) {
      return PurchaseActionResult.success;
    }
    if (!_canUseRevenueCat) {
      throw StateError('RevenueCat public key missing.');
    }

    await _ensureConfiguredForCurrentUser();

    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      await _applyCustomerInfo(result.customerInfo, source: 'purchase');
      if (state.value.isPremium) {
        return PurchaseActionResult.success;
      }
      await refreshEntitlement();
      return state.value.isPremium
          ? PurchaseActionResult.success
          : PurchaseActionResult.noEntitlement;
    } on PlatformException catch (e) {
      final code = _safeErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseActionResult.cancelled;
      }
      throw StateError(_friendlyPurchaseError(e, code));
    }
  }

  Future<PurchaseActionResult> restorePurchases() async {
    if (_user == null) {
      throw StateError('Authentication required before restore.');
    }
    if (_isDevOverride || _isAssumedProFallback) {
      return PurchaseActionResult.success;
    }
    if (!_canUseRevenueCat) {
      throw StateError('RevenueCat public key missing.');
    }

    await _ensureConfiguredForCurrentUser();

    try {
      final info = await Purchases.restorePurchases();
      await _applyCustomerInfo(info, source: 'restore');
      if (state.value.isPremium) {
        return PurchaseActionResult.success;
      }
      await refreshEntitlement();
      return state.value.isPremium
          ? PurchaseActionResult.success
          : PurchaseActionResult.noEntitlement;
    } on PlatformException catch (e) {
      final code = _safeErrorCode(e);
      throw StateError(_friendlyRestoreError(e, code));
    }
  }

  void _setState(SubscriptionState value) {
    state.value = value;
    notifyListeners();
  }

  _CachedPremium? _readCached() {
    final prefs = _prefs;
    if (prefs == null) return null;

    final hasPremium = prefs.containsKey(_kCachedPremium);
    final millis = prefs.getInt(_kCachedValidatedAt);
    if (!hasPremium || millis == null) return null;

    final last = DateTime.fromMillisecondsSinceEpoch(millis);
    final age = DateTime.now().difference(last);
    final premium = prefs.getBool(_kCachedPremium) ?? false;

    if (age > offlineGrace) {
      return _CachedPremium(
        isPremium: false,
        needsRefresh: true,
        lastValidatedAt: last,
      );
    }

    return _CachedPremium(
      isPremium: premium,
      needsRefresh: false,
      lastValidatedAt: last,
    );
  }

  Future<void> _writeCache(bool premium, DateTime lastValidatedAt) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setBool(_kCachedPremium, premium);
    await prefs.setInt(
      _kCachedValidatedAt,
      lastValidatedAt.millisecondsSinceEpoch,
    );
  }

  void _attachCustomerInfoListenerIfNeeded() {
    if (_customerInfoListenerAttached) return;
    Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdated);
    _customerInfoListenerAttached = true;
  }

  Future<void> _onCustomerInfoUpdated(CustomerInfo info) async {
    await _applyCustomerInfo(info, source: 'customer_info_listener');
  }

  Future<void> _ensureConfiguredForCurrentUser() async {
    final user = _user;
    if (user == null) {
      throw StateError('Authentication required before purchase.');
    }
    if (_configured) return;

    await bindAuthenticatedUser(user);
    if (!_configured) {
      throw StateError('RevenueCat is not configured yet. Please try again.');
    }
  }

  Future<void> _applyCustomerInfo(
    CustomerInfo info, {
    required String source,
  }) async {
    final entitlement = info.entitlements.active[entitlementName];
    final active = entitlement != null && entitlement.isActive;
    final activeProductIdentifier = entitlement?.productIdentifier;
    final entitlementExpirationDate = _parseIsoDate(
      entitlement?.expirationDate,
    );
    final latestPurchaseDate = _parseIsoDate(entitlement?.latestPurchaseDate);
    final unsubscribeDetectedAt = _parseIsoDate(
      entitlement?.unsubscribeDetectedAt,
    );
    final billingIssueDetectedAt = _parseIsoDate(
      entitlement?.billingIssueDetectedAt,
    );
    final now = DateTime.now();
    await _writeCache(active, now);
    _setState(
      state.value.copyWith(
        loading: false,
        isPremium: active,
        needsRefresh: false,
        lastValidatedAt: now,
        activeProductIdentifier: activeProductIdentifier,
        entitlementExpirationDate: entitlementExpirationDate,
        entitlementWillRenew: entitlement?.willRenew,
        latestPurchaseDate: latestPurchaseDate,
        unsubscribeDetectedAt: unsubscribeDetectedAt,
        billingIssueDetectedAt: billingIssueDetectedAt,
        clearEntitlementDetails: !active,
        source: source,
        clearError: true,
      ),
    );
  }

  DateTime? _parseIsoDate(String? value) {
    if (value == null || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    return parsed?.toLocal();
  }

  PurchasesErrorCode _safeErrorCode(PlatformException e) {
    try {
      return PurchasesErrorHelper.getErrorCode(e);
    } catch (_) {
      return PurchasesErrorCode.unknownError;
    }
  }

  String _friendlyPurchaseError(PlatformException e, PurchasesErrorCode code) {
    switch (code) {
      case PurchasesErrorCode.storeProblemError:
      case PurchasesErrorCode.productNotAvailableForPurchaseError:
      case PurchasesErrorCode.configurationError:
        return 'Purchase failed due to store configuration. Check RevenueCat products and offering mapping.';
      case PurchasesErrorCode.networkError:
      case PurchasesErrorCode.offlineConnectionError:
        return 'Purchase failed due to network connectivity. Try again online.';
      case PurchasesErrorCode.purchaseNotAllowedError:
      case PurchasesErrorCode.insufficientPermissionsError:
        return 'Purchases are not allowed on this device/account.';
      default:
        final message = (e.message ?? '').trim();
        if (message.isNotEmpty) {
          return 'Purchase failed: $message';
        }
        return 'Purchase failed. Please try again.';
    }
  }

  String _friendlyRestoreError(PlatformException e, PurchasesErrorCode code) {
    switch (code) {
      case PurchasesErrorCode.networkError:
      case PurchasesErrorCode.offlineConnectionError:
        return 'Restore failed due to network connectivity. Try again online.';
      default:
        final message = (e.message ?? '').trim();
        if (message.isNotEmpty) {
          return 'Restore failed: $message';
        }
        return 'Restore failed. Please try again.';
    }
  }
}

class _CachedPremium {
  final bool isPremium;
  final bool needsRefresh;
  final DateTime lastValidatedAt;

  const _CachedPremium({
    required this.isPremium,
    required this.needsRefresh,
    required this.lastValidatedAt,
  });
}
