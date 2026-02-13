import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubscriptionState {
  final bool loading;
  final bool isPremium;
  final bool needsRefresh;
  final DateTime? lastValidatedAt;
  final String source;
  final String? error;

  const SubscriptionState({
    required this.loading,
    required this.isPremium,
    required this.needsRefresh,
    required this.source,
    this.lastValidatedAt,
    this.error,
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
      source: source ?? this.source,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

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
    defaultValue: true,
  );
  static const String _androidPublicKey = String.fromEnvironment(
    'RC_ANDROID_PUBLIC_KEY',
    defaultValue: '',
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
    if (Platform.isAndroid) return _androidPublicKey;
    if (Platform.isIOS) return _iosPublicKey;
    if (Platform.isMacOS) return _iosPublicKey;
    return '';
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
      final entitlement = info.entitlements.active[entitlementName];
      final active = entitlement != null && entitlement.isActive;
      final now = DateTime.now();
      await _writeCache(active, now);

      _setState(
        state.value.copyWith(
          loading: false,
          isPremium: active,
          needsRefresh: false,
          lastValidatedAt: now,
          source: 'revenuecat',
          clearError: true,
        ),
      );
    } catch (e) {
      final cached = _readCached();
      if (cached != null) {
        _setState(
          state.value.copyWith(
            loading: false,
            isPremium: cached.isPremium,
            needsRefresh: cached.needsRefresh,
            lastValidatedAt: cached.lastValidatedAt,
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
            source: 'refresh_failed',
            error: e.toString(),
          ),
        );
      }
    }
  }

  Future<Offerings?> fetchOfferings() async {
    if (_isDevOverride || _isAssumedProFallback) return null;
    if (!_canUseRevenueCat || !_configured || _user == null) return null;

    final offerings = await Purchases.getOfferings();
    return offerings;
  }

  Future<void> purchasePackage(Package package) async {
    if (_user == null) {
      throw StateError('Authentication required before purchase.');
    }
    if (_isDevOverride || _isAssumedProFallback) return;
    if (!_canUseRevenueCat) {
      throw StateError('RevenueCat public key missing.');
    }

    await Purchases.purchase(PurchaseParams.package(package));
    await refreshEntitlement();
  }

  Future<void> restorePurchases() async {
    if (_user == null) {
      throw StateError('Authentication required before restore.');
    }
    if (_isDevOverride || _isAssumedProFallback) return;
    if (!_canUseRevenueCat) {
      throw StateError('RevenueCat public key missing.');
    }

    await Purchases.restorePurchases();
    await refreshEntitlement();
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
    final entitlement = info.entitlements.active[entitlementName];
    final active = entitlement != null && entitlement.isActive;
    final now = DateTime.now();
    await _writeCache(active, now);
    _setState(
      state.value.copyWith(
        loading: false,
        isPremium: active,
        needsRefresh: false,
        lastValidatedAt: now,
        source: 'customer_info_listener',
        clearError: true,
      ),
    );
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
