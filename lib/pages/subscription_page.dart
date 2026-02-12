import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import 'legal_pages.dart';
import 'plan_comparison_page.dart';
import '../subscription_service.dart';

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
      setState(() {
        _packages = _sortPackages(packages);
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingProducts = false;
      });
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
    if (id.contains('yearly')) return 1;
    if (id.contains('lifetime')) return 2;
    return 99;
  }

  bool _isYearly(Package p) {
    return p.storeProduct.identifier.toLowerCase().contains('yearly');
  }

  Future<void> _buy(Package p) async {
    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      await widget.subscription.purchasePackage(p);
      if (!mounted) return;
      if (!widget.asTab) {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Premium unlocked.')));
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _processing = false;
      });
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
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _processing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.asTab ? null : AppBar(title: const Text('Go Premium')),
      body: ValueListenableBuilder<SubscriptionState>(
        valueListenable: widget.subscription.state,
        builder: (context, subState, _) {
          return RefreshIndicator(
            onRefresh: () async {
              await widget.subscription.refreshEntitlement();
              await _loadProducts();
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Snooze Premium',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subState.isPremium
                            ? 'You have active pro access.'
                            : 'Unlock unlimited reminders, advanced recurrence, analytics, and cloud sync.',
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PlanComparisonPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.compare_arrows),
                        label: const Text('Compare Free vs Pro'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (subState.source == 'assumed_pro_no_revenuecat')
                  const AppInlineMessage(
                    text:
                        'Development mode is active: Premium access is assumed because RevenueCat keys are not set. Cloud sync is enabled for this mode.',
                    icon: Icons.developer_mode,
                  )
                else if (_loadingProducts)
                  const AppLoadingIndicator(label: 'Loading plans...')
                else if (_packages.isEmpty)
                  const AppInlineMessage(
                    text:
                        'Products are not available yet. Configure RevenueCat offerings and store products, then pull to refresh.',
                    icon: Icons.info_outline,
                  )
                else
                  ..._packages.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PackageCard(
                        package: p,
                        highlighted: _isYearly(p),
                        busy: _processing,
                        onTap: () => _buy(p),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _processing ? null : _restore,
                  child: const Text('Restore Purchases'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const TermsPage()),
                        );
                      },
                      child: const Text('Terms of Service'),
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
                if (subState.error != null) ...[
                  const SizedBox(height: 8),
                  AppInlineMessage(
                    text: subState.error!,
                    icon: Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  AppInlineMessage(
                    text: _error!,
                    icon: Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final Package package;
  final bool highlighted;
  final bool busy;
  final VoidCallback onTap;

  const _PackageCard({
    required this.package,
    required this.highlighted,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final id = package.storeProduct.identifier;
    final title = package.storeProduct.title;
    final desc = package.storeProduct.description;
    final price = package.storeProduct.priceString;

    return AppSurfaceCard(
      onTap: busy ? null : onTap,
      color: highlighted ? cs.primaryContainer.withValues(alpha: 0.65) : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.isNotEmpty ? title : id,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (highlighted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Best value',
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(desc.isEmpty ? id : desc),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            price,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
