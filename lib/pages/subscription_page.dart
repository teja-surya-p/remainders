import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import '../subscription_service.dart';
import '../theme/app_tokens.dart';
import 'legal_pages.dart';
import 'plan_comparison_page.dart';

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
      final current = offerings?.current;
      final packages = current?.availablePackages ?? const <Package>[];
      final sorted = _sortPackages(packages);
      setState(() {
        _packages = sorted;
        _selectedId = _selectedId ?? _defaultPackageId(sorted);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loadingProducts = false);
    }
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
    final id = p.storeProduct.identifier.toLowerCase();
    if (id.contains('monthly')) return 0;
    if (id.contains('yearly') || id.contains('annual')) return 1;
    if (id.contains('lifetime')) return 2;
    return 99;
  }

  String? _defaultPackageId(List<Package> packages) {
    for (final p in packages) {
      if (_isYearly(p)) return p.identifier;
    }
    return packages.isEmpty ? null : packages.first.identifier;
  }

  bool _isYearly(Package p) {
    final id = p.storeProduct.identifier.toLowerCase();
    return id.contains('yearly') || id.contains('annual');
  }

  bool _isLifetime(Package p) {
    final id = p.storeProduct.identifier.toLowerCase();
    return id.contains('lifetime');
  }

  bool _isMonthly(Package p) {
    return p.storeProduct.identifier.toLowerCase().contains('monthly');
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
      await widget.subscription.purchasePackage(selected);
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() => _processing = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      await widget.subscription.restorePurchases();
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() => _processing = false);
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
              widget.asTab ? 112 : 24,
            ),
            children: [
              _header(context, subState),
              const SizedBox(height: 12),
              if (subState.isPremium)
                _activeState(context)
              else ...[
                _featureCard(context),
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

  Widget _activeState(BuildContext context) {
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
          OutlinedButton(
            onPressed: _processing ? null : _restore,
            child: const Text('Manage / Restore purchases'),
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
    if (_isMonthly(p)) return 'Monthly';
    if (_isYearly(p)) return 'Yearly';
    if (_isLifetime(p)) return 'Lifetime';
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
