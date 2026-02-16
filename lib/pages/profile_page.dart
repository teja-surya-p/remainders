import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../components/common/app_ui.dart';
import '../subscription_service.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_service.dart';
import 'sharing_page.dart';
import 'subscription_page.dart';

class ProfilePage extends StatelessWidget {
  final bool asTab;
  final VoidCallback? onOpenSubscription;

  const ProfilePage({super.key, this.asTab = false, this.onOpenSubscription});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    final body = _ProfileBody(
      user: user,
      asTab: asTab,
      onOpenSubscription: onOpenSubscription,
    );

    if (asTab) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: body,
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final User user;
  final bool asTab;
  final VoidCallback? onOpenSubscription;

  const _ProfileBody({
    required this.user,
    required this.asTab,
    required this.onOpenSubscription,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = AppTone.of(context);

    return ValueListenableBuilder<SubscriptionState>(
      valueListenable: AppServices.subscription.state,
      builder: (context, subState, _) {
        final isPremium = subState.isPremium;
        final cloudEnabled = AppServices.subscription.shouldUseCloudSync;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            asTab ? 56 : 16,
            16,
            asTab ? 112 : 24,
          ),
          children: [
            Text(
              'Profile',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            AppSurfaceCard(
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initials(user),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName?.trim().isNotEmpty == true
                              ? user.displayName!
                              : 'Snooze user',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.email ?? 'No email',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: tone.mutedText),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isPremium
                          ? cs.primary.withValues(alpha: 0.12)
                          : cs.secondary.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isPremium ? 'Pro' : 'Free',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isPremium ? cs.primary : tone.mutedText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cloud Sync',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: tone.mutedText),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: (cloudEnabled ? tone.success : tone.mutedText)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          cloudEnabled
                              ? Icons.cloud_done_rounded
                              : Icons.cloud_off_rounded,
                          size: 20,
                          color: cloudEnabled ? tone.success : tone.mutedText,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cloudEnabled ? 'Connected' : 'Local only',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              cloudEnabled
                                  ? 'Firestore sync active'
                                  : 'Data is stored on this device',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: tone.mutedText),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: cloudEnabled ? tone.success : tone.mutedText,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: AppServices.theme,
              builder: (context, _) {
                final selected = AppServices.theme.setting;
                return AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appearance',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: tone.mutedText),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _ThemeOption(
                            label: 'Light',
                            icon: Icons.light_mode_rounded,
                            selected: selected == AppThemeSetting.light,
                            onTap: () => AppServices.theme.setThemeSetting(
                              AppThemeSetting.light,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ThemeOption(
                            label: 'Dark',
                            icon: Icons.dark_mode_rounded,
                            selected: selected == AppThemeSetting.dark,
                            onTap: () => AppServices.theme.setThemeSetting(
                              AppThemeSetting.dark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ThemeOption(
                            label: 'System',
                            icon: Icons.brightness_auto_rounded,
                            selected: selected == AppThemeSetting.system,
                            onTap: () => AppServices.theme.setThemeSetting(
                              AppThemeSetting.system,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            if (!isPremium)
              _MenuTile(
                icon: Icons.workspace_premium_rounded,
                iconColor: cs.primary,
                iconBg: cs.primary.withValues(alpha: 0.12),
                label: 'Upgrade to Pro',
                labelColor: cs.primary,
                onTap: () {
                  if (onOpenSubscription != null) {
                    onOpenSubscription!();
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SubscriptionPage(
                        subscription: AppServices.subscription,
                      ),
                    ),
                  );
                },
              ),
            _MenuTile(
              icon: Icons.link_rounded,
              iconColor: tone.chart2,
              iconBg: tone.chart2.withValues(alpha: 0.13),
              label: 'Invite & Share',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SharingPage(
                      onOpenSubscription: onOpenSubscription ?? () {},
                    ),
                  ),
                );
              },
            ),
            _MenuTile(
              icon: Icons.notifications_active_rounded,
              iconColor: tone.chart3,
              iconBg: tone.chart3.withValues(alpha: 0.13),
              label: 'Notification Settings',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Manage notifications from device settings.'),
                  ),
                );
              },
            ),
            _MenuTile(
              icon: Icons.sync_rounded,
              iconColor: tone.chart4,
              iconBg: tone.chart4.withValues(alpha: 0.13),
              label: 'Refresh Subscription',
              onTap: () async {
                await AppServices.subscription.refreshEntitlement();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Subscription refreshed')),
                  );
                }
              },
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (!context.mounted) return;
                if (!asTab) {
                  Navigator.pop(context);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: cs.error.withValues(alpha: 0.1),
                foregroundColor: cs.error,
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign Out'),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Snooze v1.0.1',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tone.mutedText.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _initials(User user) {
    final name = user.displayName?.trim() ?? '';
    if (name.isNotEmpty) {
      final chunks = name
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty);
      final take = chunks.take(2).map((p) => p[0].toUpperCase()).join();
      if (take.isNotEmpty) return take;
    }
    final email = user.email ?? 'SU';
    return email.substring(0, 2).toUpperCase();
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = AppTone.of(context);
    return Expanded(
      child: AppSurfaceCard(
        dense: true,
        color: selected
            ? cs.primary.withValues(alpha: 0.12)
            : cs.secondary.withValues(alpha: 0.6),
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, size: 20, color: selected ? cs.primary : tone.mutedText),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected ? cs.primary : tone.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final Color? labelColor;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppSurfaceCard(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: labelColor ?? cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppTone.of(context).mutedText,
            ),
          ],
        ),
      ),
    );
  }
}
