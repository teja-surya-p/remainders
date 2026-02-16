import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import '../subscription_service.dart';
import '../theme/app_tokens.dart';
import 'legal_pages.dart';
import 'plan_comparison_page.dart';

enum _PlanKind { monthly, yearly, lifetime }

class SubscriptionPage extends StatefulWidget {
  final SubscriptionService subscription;
  final bool asTab;

  const SubscriptionPage({
    super.key,
    required this.subscription,
    this.asTab = false,
  });

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  static const String _androidPackageName = 'com.suryatejap24.snooze';
  bool _loadingProducts = true;
  String? _error;
  List<Package> _packages = const [];
  String? _selectedId;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loadingProducts = true;
      _error = null;
    });

    try {
      final offerings = await widget.subscription.fetchOfferings();
      final sorted = _resolvePackagesFromOfferings(offerings);
      setState(() {
        _packages = sorted;
        _selectedId = _selectedId ?? _defaultPackageId(sorted);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingProducts = false);
      }
    }
  }

  List<Package> _resolvePackagesFromOfferings(Offerings? offerings) {
    if (offerings == null) return const <Package>[];

    final current =
        offerings.current ??
        (offerings.all.isNotEmpty ? offerings.all.values.first : null);

    final currentPackages = List<Package>.from(
      current?.availablePackages ?? const <Package>[],
    );
    final allPackages = <Package>[];
    final seen = <String>{};

    void addUnique(Iterable<Package> source) {
      for (final p in source) {
        final key = _packageKey(p);
        if (seen.add(key)) {
          allPackages.add(p);
        }
      }
    }

    addUnique(currentPackages);
    for (final offering in offerings.all.values) {
      addUnique(offering.availablePackages);
    }

    final planPackages = <_PlanKind, Package>{};
    for (final kind in const [
      _PlanKind.monthly,
      _PlanKind.yearly,
      _PlanKind.lifetime,
    ]) {
      final selectedFromCurrent = _selectBestPackageForKind(
        kind: kind,
        candidates: currentPackages,
      );
      final selected =
          selectedFromCurrent ??
          _selectBestPackageForKind(kind: kind, candidates: allPackages);
      if (selected != null) {
        planPackages[kind] = selected;
      }
    }

    final ordered = <Package>[];
    final orderedKeys = <String>{};
    void addOrdered(Package package) {
      final key = _packageKey(package);
      if (orderedKeys.add(key)) {
        ordered.add(package);
      }
    }

    for (final kind in const [
      _PlanKind.monthly,
      _PlanKind.yearly,
      _PlanKind.lifetime,
    ]) {
      final plan = planPackages[kind];
      if (plan != null) {
        addOrdered(plan);
      }
    }

    for (final p in _sortPackages(currentPackages)) {
      addOrdered(p);
    }
    for (final p in _sortPackages(allPackages)) {
      addOrdered(p);
    }

    if (ordered.isEmpty) {
      return _sortPackages(allPackages);
    }

    return ordered;
  }

  String _packageKey(Package package) {
    return '${package.identifier}|${package.storeProduct.identifier}';
  }

  Package? _selectBestPackageForKind({
    required _PlanKind kind,
    required List<Package> candidates,
  }) {
    final matching = candidates
        .where((candidate) {
          return _detectPlanKind(candidate) == kind;
        })
        .toList(growable: false);
    if (matching.isEmpty) return null;

    final canonical = matching
        .where((candidate) {
          return _isCanonicalIdMatch(kind, candidate);
        })
        .toList(growable: false);

    final source = canonical.isNotEmpty ? canonical : matching;
    final pool = source;

    pool.sort((a, b) {
      final byPrice = a.storeProduct.price.compareTo(b.storeProduct.price);
      if (byPrice != 0) return byPrice;
      return a.identifier.compareTo(b.identifier);
    });
    return pool.first;
  }

  bool _isCanonicalIdMatch(_PlanKind kind, Package package) {
    final storeId = package.storeProduct.identifier.toLowerCase();
    final storeRoot = storeId.split(':').first;
    final packageId = package.identifier.toLowerCase();
    switch (kind) {
      case _PlanKind.monthly:
        return package.packageType == PackageType.monthly ||
            storeRoot == 'monthly' ||
            packageId.endsWith('.monthly');
      case _PlanKind.yearly:
        return package.packageType == PackageType.annual ||
            storeRoot == 'yearly' ||
            storeRoot == 'annual' ||
            packageId.endsWith('.annual');
      case _PlanKind.lifetime:
        return package.packageType == PackageType.lifetime ||
            storeRoot == 'lifetime' ||
            packageId.endsWith('.lifetime');
    }
  }

  _PlanKind? _detectPlanKind(Package p) {
    switch (p.packageType) {
      case PackageType.monthly:
        return _PlanKind.monthly;
      case PackageType.annual:
        return _PlanKind.yearly;
      case PackageType.lifetime:
        return _PlanKind.lifetime;
      default:
        break;
    }

    final tokens = [
      _normalizePlanToken(p.identifier),
      _normalizePlanToken(p.storeProduct.identifier),
      _normalizePlanToken(p.storeProduct.title),
    ].join(' ');

    if (_containsAny(tokens, const [
      'lifetime',
      'life time',
      'one time',
      'onetime',
      'forever',
      'permanent',
    ])) {
      return _PlanKind.lifetime;
    }
    if (_containsAny(tokens, const ['yearly', 'annual', 'year'])) {
      return _PlanKind.yearly;
    }
    if (_containsAny(tokens, const ['monthly', 'month'])) {
      return _PlanKind.monthly;
    }

    return null;
  }

  String _normalizePlanToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[_\.\-:]'), ' ');
  }

  bool _containsAny(String value, List<String> needles) {
    for (final needle in needles) {
      if (value.contains(needle)) return true;
    }
    return false;
  }

  List<Package> _sortPackages(List<Package> packages) {
    final out = [...packages];
    out.sort((a, b) {
      final ai = _packageOrder(a);
      final bi = _packageOrder(b);
      if (ai != bi) return ai.compareTo(bi);
      return a.storeProduct.price.compareTo(b.storeProduct.price);
    });
    return out;
  }

  int _packageOrder(Package p) {
    final kind = _detectPlanKind(p);
    if (kind == _PlanKind.monthly) return 0;
    if (kind == _PlanKind.yearly) return 1;
    if (kind == _PlanKind.lifetime) return 2;
    return 99;
  }

  String? _defaultPackageId(List<Package> packages) {
    for (final p in packages) {
      if (_isYearly(p)) return p.identifier;
    }
    return packages.isEmpty ? null : packages.first.identifier;
  }

  bool _isYearly(Package p) {
    return _detectPlanKind(p) == _PlanKind.yearly;
  }

  _PlanKind? _planFromProductIdentifier(String? productIdentifier) {
    if (productIdentifier == null || productIdentifier.isEmpty) return null;
    final token = _normalizePlanToken(productIdentifier);
    if (_containsAny(token, const ['lifetime', 'life time', 'forever'])) {
      return _PlanKind.lifetime;
    }
    if (_containsAny(token, const ['yearly', 'annual', 'year'])) {
      return _PlanKind.yearly;
    }
    if (_containsAny(token, const ['monthly', 'month'])) {
      return _PlanKind.monthly;
    }
    return null;
  }

  Package? _packageForKind(_PlanKind kind) {
    for (final package in _packages) {
      if (_detectPlanKind(package) == kind) {
        return package;
      }
    }
    return null;
  }

  NumberFormat? _currencyFormatFor(Package? package) {
    if (package == null) return null;
    final code = package.storeProduct.currencyCode;
    return NumberFormat.simpleCurrency(name: code);
  }

  String _formatAmount(double value, Package? referencePackage) {
    final formatter = _currencyFormatFor(referencePackage);
    if (formatter != null) {
      return formatter.format(value);
    }
    return value.toStringAsFixed(2);
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM d, y • h:mm a').format(date);
  }

  String _planName(_PlanKind? kind) {
    switch (kind) {
      case _PlanKind.monthly:
        return 'Monthly';
      case _PlanKind.yearly:
        return 'Yearly';
      case _PlanKind.lifetime:
        return 'Lifetime';
      case null:
        return 'Pro';
    }
  }

  Future<void> _cancelSubscriptionWithConfirmation({
    required _PlanKind planKind,
    required String? productIdentifier,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancel subscription?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'If you cancel your ${_planName(planKind)} plan, you will lose:',
              ),
              const SizedBox(height: 10),
              const Text('• Unlimited active reminders (back to 5/day)'),
              const Text('• Advanced recurrence controls'),
              const Text('• Full analytics and collaboration tools'),
              const Text('• Premium cloud sync writes'),
              const SizedBox(height: 10),
              const Text('Are you sure you want to continue?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep my plan'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue to cancel'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final opened = await _openSubscriptionManagement(productIdentifier);
    if (!mounted) return;

    if (opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Subscription management opened. Cancel there to stop auto-renewal.',
          ),
        ),
      );
    } else {
      setState(() {
        _error = 'Could not open subscription management page.';
      });
    }
  }

  Future<bool> _openSubscriptionManagement(String? productIdentifier) async {
    if (Platform.isAndroid) {
      final sku = productIdentifier?.split(':').first.trim();
      final query = <String, String>{'package': _androidPackageName};
      if (sku != null && sku.isNotEmpty) {
        query['sku'] = sku;
      }
      final uri = Uri.https(
        'play.google.com',
        '/store/account/subscriptions',
        query,
      );
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    if (Platform.isIOS) {
      final uri = Uri.parse('https://apps.apple.com/account/subscriptions');
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    return false;
  }

  Future<void> _buySelected() async {
    if (_processing) return;
    final selected = _packages
        .where((p) => p.identifier == _selectedId)
        .firstOrNull;
    if (selected == null) {
      setState(() {
        _error = 'No plan selected.';
      });
      return;
    }

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final result = await widget.subscription.purchasePackage(selected);
      if (!mounted) return;
      if (result == PurchaseActionResult.cancelled) {
        return;
      }
      if (result == PurchaseActionResult.noEntitlement) {
        setState(() {
          _error =
              'Purchase succeeded but entitlement is still inactive. Verify RevenueCat entitlement mapping to "pro_access".';
        });
        return;
      }
      if (!widget.asTab) {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Premium unlocked.')));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _restore() async {
    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final result = await widget.subscription.restorePurchases();
      if (!mounted) return;
      if (result == PurchaseActionResult.noEntitlement) {
        setState(() {
          _error = 'No active purchases were found to restore.';
        });
        return;
      }
      if (widget.subscription.isPremium) {
        if (!widget.asTab) {
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Purchases restored.')));
        }
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ValueListenableBuilder<SubscriptionState>(
      valueListenable: widget.subscription.state,
      builder: (context, subState, _) {
        return RefreshIndicator(
          onRefresh: () async {
            await widget.subscription.refreshEntitlement();
            await _loadProducts();
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              widget.asTab ? 56 : 16,
              16,
              widget.asTab ? 168 : 24,
            ),
            children: [
              _header(context, subState),
              const SizedBox(height: 12),
              if (subState.isPremium)
                _activeState(context, subState)
              else ...[
                _featureCard(context),
                const SizedBox(height: 10),
                if (subState.source == 'missing_keys')
                  const AppInlineMessage(
                    text:
                        'RevenueCat public key is missing. Set RC_ANDROID_PUBLIC_KEY and RC_IOS_PUBLIC_KEY (or RC_PUBLIC_KEY) to enable live purchases.',
                    icon: Icons.key_rounded,
                  )
                else if (subState.source == 'awaiting_user')
                  const AppInlineMessage(
                    text:
                        'Sign in with an authenticated account before purchasing.',
                    icon: Icons.person_rounded,
                  )
                else
                  const SizedBox.shrink(),
                if (subState.source == 'missing_keys' ||
                    subState.source == 'awaiting_user')
                  const SizedBox(height: 10),
                if (subState.source == 'assumed_pro_no_revenuecat')
                  const AppInlineMessage(
                    text:
                        'Development mode is active: Premium is currently assumed while RevenueCat keys are missing.',
                    icon: Icons.developer_mode_rounded,
                  )
                else if (_loadingProducts)
                  const AppLoadingIndicator(label: 'Loading plans...')
                else if (_packages.isEmpty)
                  const AppInlineMessage(
                    text:
                        'Products are not available yet. Configure RevenueCat offerings and store products, then refresh.',
                    icon: Icons.info_outline,
                  )
                else
                  ..._packages.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PlanCard(
                        package: p,
                        selected: p.identifier == _selectedId,
                        highlighted: _isYearly(p),
                        onTap: () => setState(() => _selectedId = p.identifier),
                        label: _labelFor(p),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _processing ? null : _restore,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Restore purchases'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PlanComparisonPage(),
                      ),
                    );
                  },
                  child: const Text('Show Free vs Pro comparison'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const TermsPage()),
                        );
                      },
                      child: const Text('Terms of Use'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PrivacyPage(),
                          ),
                        );
                      },
                      child: const Text('Privacy Policy'),
                    ),
                  ],
                ),
              ],
              if (subState.error != null) ...[
                const SizedBox(height: 8),
                AppInlineMessage(
                  text: subState.error!,
                  icon: Icons.error_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                AppInlineMessage(
                  text: _error!,
                  icon: Icons.error_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
              ],
            ],
          ),
        );
      },
    );

    if (widget.asTab) {
      return Scaffold(body: content, bottomSheet: _cta());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Go Premium')),
      body: content,
      bottomSheet: _cta(),
    );
  }

  Widget _header(BuildContext context, SubscriptionState subState) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.workspace_premium_rounded,
            color: cs.onPrimary,
            size: 34,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subState.isPremium ? 'Snooze Pro Active' : 'Upgrade to Pro',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          subState.isPremium
              ? 'All premium features are unlocked.'
              : 'Unlock your full productivity potential.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _featureCard(BuildContext context) {
    return AppSurfaceCard(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _FeatureLine(
            icon: Icons.all_inclusive_rounded,
            text: 'Unlimited active reminders',
          ),
          _FeatureLine(
            icon: Icons.repeat_rounded,
            text: 'Advanced recurring controls',
          ),
          _FeatureLine(
            icon: Icons.analytics_rounded,
            text: 'Full analytics and insights',
          ),
          _FeatureLine(
            icon: Icons.groups_rounded,
            text: 'Shared reminders and collaboration',
          ),
          _FeatureLine(
            icon: Icons.cloud_done_rounded,
            text: 'Real-time cloud sync',
          ),
          _FeatureLine(
            icon: Icons.verified_user_rounded,
            text: 'RevenueCat entitlement validation',
          ),
        ],
      ),
    );
  }

  Widget _activeState(BuildContext context, SubscriptionState subState) {
    final activePlanKind = _planFromProductIdentifier(
      subState.activeProductIdentifier,
    );
    final monthly = _packageForKind(_PlanKind.monthly);
    final yearly = _packageForKind(_PlanKind.yearly);
    final lifetime = _packageForKind(_PlanKind.lifetime);

    final statusLines = <String>[];
    if (activePlanKind == _PlanKind.lifetime) {
      statusLines.add('Active plan: Lifetime (no expiry)');
    } else if (subState.entitlementExpirationDate != null) {
      statusLines.add(
        'Active until ${_formatDate(subState.entitlementExpirationDate!)}',
      );
      if (subState.entitlementWillRenew == true) {
        statusLines.add('Auto-renew is ON');
      } else if (subState.entitlementWillRenew == false) {
        statusLines.add('Auto-renew is OFF');
      }
    } else {
      statusLines.add('Active plan: ${_planName(activePlanKind)}');
    }

    if (subState.latestPurchaseDate != null) {
      statusLines.add(
        'Last purchase: ${_formatDate(subState.latestPurchaseDate!)}',
      );
    }

    if (subState.unsubscribeDetectedAt != null) {
      statusLines.add(
        'Cancellation detected on ${_formatDate(subState.unsubscribeDetectedAt!)}',
      );
    }

    final suggestions = <Widget>[];
    if (activePlanKind == _PlanKind.monthly &&
        monthly != null &&
        yearly != null &&
        lifetime != null) {
      final monthlyPrice = monthly.storeProduct.price;
      final yearlyIfMonthly = monthlyPrice * 12;
      final yearlySavings = yearlyIfMonthly - yearly.storeProduct.price;
      if (yearlySavings > 0) {
        suggestions.add(
          _PlanSuggestionCard(
            icon: Icons.trending_up_rounded,
            title: 'Yearly discount available',
            message:
                'Yearly is ${yearly.storeProduct.priceString} instead of ${_formatAmount(yearlyIfMonthly, monthly)} per year on monthly. You save about ${_formatAmount(yearlySavings, monthly)}.',
          ),
        );
      }

      final twoYearsMonthly = monthlyPrice * 24;
      final lifetimeSavings = twoYearsMonthly - lifetime.storeProduct.price;
      final breakEvenMonths = monthlyPrice > 0
          ? lifetime.storeProduct.price / monthlyPrice
          : null;
      suggestions.add(
        _PlanSuggestionCard(
          icon: Icons.workspace_premium_rounded,
          title: 'Lifetime option',
          message:
              'Lifetime is ${lifetime.storeProduct.priceString} one-time.${breakEvenMonths != null ? ' Break-even is about ${breakEvenMonths.toStringAsFixed(1)} months of monthly.' : ''}${lifetimeSavings > 0 ? ' Compared to 2 years of monthly, you save about ${_formatAmount(lifetimeSavings, monthly)}.' : ''}',
        ),
      );
    } else if (activePlanKind == _PlanKind.yearly &&
        monthly != null &&
        yearly != null &&
        lifetime != null) {
      final yearlyIfMonthly = monthly.storeProduct.price * 12;
      final yearlySavings = yearlyIfMonthly - yearly.storeProduct.price;
      if (yearlySavings > 0) {
        suggestions.add(
          _PlanSuggestionCard(
            icon: Icons.check_circle_outline_rounded,
            title: 'You are already saving with yearly',
            message:
                'Yearly at ${yearly.storeProduct.priceString} saves about ${_formatAmount(yearlySavings, monthly)} versus paying monthly for a year.',
          ),
        );
      }

      final yearlyPrice = yearly.storeProduct.price;
      final breakEvenYears = yearlyPrice > 0
          ? lifetime.storeProduct.price / yearlyPrice
          : null;
      suggestions.add(
        _PlanSuggestionCard(
          icon: Icons.auto_awesome_rounded,
          title: 'Lifetime upgrade insight',
          message:
              'Lifetime is ${lifetime.storeProduct.priceString} one-time.${breakEvenYears != null ? ' Break-even is about ${breakEvenYears.toStringAsFixed(1)} years of yearly renewals.' : ''}',
        ),
      );
    } else if (activePlanKind == _PlanKind.lifetime) {
      suggestions.add(
        const _PlanSuggestionCard(
          icon: Icons.verified_rounded,
          title: 'Best long-term value unlocked',
          message:
              'You are on Lifetime, so there is no recurring billing and no renewal management required.',
        ),
      );
    }

    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FeatureLine(
            icon: Icons.check_circle_rounded,
            text: 'Premium entitlement is active',
          ),
          const _FeatureLine(
            icon: Icons.check_circle_rounded,
            text: 'Unlimited reminders enabled',
          ),
          const _FeatureLine(
            icon: Icons.check_circle_rounded,
            text: 'Cloud sync and collaboration enabled',
          ),
          const SizedBox(height: 8),
          Text(
            'Subscription details',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          ...statusLines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line, style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
          if (subState.billingIssueDetectedAt != null) ...[
            const SizedBox(height: 8),
            AppInlineMessage(
              text:
                  'Billing issue detected on ${_formatDate(subState.billingIssueDetectedAt!)}. Update your payment method in your store account.',
              icon: Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
          ],
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...suggestions.map(
              (card) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: card,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _processing ? null : _restore,
                child: const Text('Manage / Restore purchases'),
              ),
              if (activePlanKind == _PlanKind.monthly ||
                  activePlanKind == _PlanKind.yearly)
                OutlinedButton.icon(
                  onPressed: _processing
                      ? null
                      : () => _cancelSubscriptionWithConfirmation(
                          planKind: activePlanKind!,
                          productIdentifier: subState.activeProductIdentifier,
                        ),
                  icon: const Icon(Icons.cancel_rounded),
                  label: const Text('Cancel subscription'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cta() {
    return ValueListenableBuilder<SubscriptionState>(
      valueListenable: widget.subscription.state,
      builder: (context, subState, _) {
        if (subState.isPremium) {
          return const SizedBox.shrink();
        }
        final selected = _packages
            .where((p) => p.identifier == _selectedId)
            .firstOrNull;
        final suffix = selected == null
            ? ''
            : ' - ${selected.storeProduct.priceString}';

        return SafeArea(
          top: false,
          child: Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: EdgeInsets.fromLTRB(16, 10, 16, widget.asTab ? 84 : 12),
            child: FilledButton(
              onPressed: _processing || _loadingProducts || _packages.isEmpty
                  ? null
                  : _buySelected,
              child: Text(_processing ? 'Processing...' : 'Subscribe$suffix'),
            ),
          ),
        );
      },
    );
  }

  String _labelFor(Package p) {
    final kind = _detectPlanKind(p);
    if (kind == _PlanKind.monthly) return 'Monthly';
    if (kind == _PlanKind.yearly) return 'Yearly';
    if (kind == _PlanKind.lifetime) return 'Lifetime';
    return p.storeProduct.title;
  }
}

class _PlanCard extends StatelessWidget {
  final Package package;
  final bool selected;
  final bool highlighted;
  final String label;
  final VoidCallback onTap;

  const _PlanCard({
    required this.package,
    required this.selected,
    required this.highlighted,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppSurfaceCard(
      onTap: onTap,
      color: selected ? cs.primary.withValues(alpha: 0.1) : null,
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: selected ? cs.primary : AppTone.of(context).mutedText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (highlighted) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Best Value',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: cs.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  package.storeProduct.description.isNotEmpty
                      ? package.storeProduct.description
                      : package.storeProduct.identifier,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            package.storeProduct.priceString,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PlanSuggestionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _PlanSuggestionCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
