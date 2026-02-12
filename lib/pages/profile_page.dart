import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../components/common/app_ui.dart';
import 'subscription_page.dart';
import '../theme/theme_service.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    final providers = user.providerData;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            onPressed: () async {
              await AppServices.subscription.refreshEntitlement();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Subscription refreshed')),
                );
              }
            },
            icon: const Icon(Icons.sync),
            tooltip: 'Refresh subscription',
          ),
          IconButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppSurfaceCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundImage: user.photoURL != null
                      ? NetworkImage(user.photoURL!)
                      : null,
                  child: user.photoURL == null
                      ? const Icon(Icons.person, size: 32)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName ?? 'No name',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(user.email ?? 'No email'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder(
            valueListenable: AppServices.subscription.state,
            builder: (context, value, _) {
              return AppSurfaceCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Subscription'),
                  subtitle: Text(
                    value.isPremium ? 'Premium active' : 'Free plan',
                  ),
                  trailing: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SubscriptionPage(
                            subscription: AppServices.subscription,
                          ),
                        ),
                      );
                    },
                    child: const Text('Manage'),
                  ),
                ),
              );
            },
          ),
          ValueListenableBuilder(
            valueListenable: AppServices.subscription.state,
            builder: (context, value, _) {
              final cloudEnabled = AppServices.subscription.shouldUseCloudSync;
              return AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Data Pipeline',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      cloudEnabled
                          ? 'Cloud sync active (Firestore + local mirror)'
                          : 'Local-only storage active',
                    ),
                    const SizedBox(height: 4),
                    Text('Entitlement source: ${value.source}'),
                    if (cloudEnabled) ...[
                      const SizedBox(height: 6),
                      Text('Reminders: users/${user.uid}/reminders'),
                      Text('Events: users/${user.uid}/reminderEvents'),
                    ],
                  ],
                ),
              );
            },
          ),
          ListenableBuilder(
            listenable: AppServices.theme,
            builder: (context, _) {
              final selected = AppServices.theme.setting;
              return AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Theme',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose appearance mode',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<AppThemeSetting>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment<AppThemeSetting>(
                          value: AppThemeSetting.system,
                          label: Text(
                            AppServices.theme.label(AppThemeSetting.system),
                          ),
                          icon: const Icon(Icons.brightness_auto),
                        ),
                        ButtonSegment<AppThemeSetting>(
                          value: AppThemeSetting.light,
                          label: Text(
                            AppServices.theme.label(AppThemeSetting.light),
                          ),
                          icon: const Icon(Icons.light_mode),
                        ),
                        ButtonSegment<AppThemeSetting>(
                          value: AppThemeSetting.dark,
                          label: Text(
                            AppServices.theme.label(AppThemeSetting.dark),
                          ),
                          icon: const Icon(Icons.dark_mode),
                        ),
                      ],
                      selected: {selected},
                      onSelectionChanged: (value) {
                        if (value.isEmpty) return;
                        AppServices.theme.setThemeSetting(value.first);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          _InfoTile(label: 'UID', value: user.uid),
          _InfoTile(
            label: 'Email verified',
            value: user.emailVerified ? 'Yes' : 'No',
          ),
          _InfoTile(label: 'Phone', value: user.phoneNumber ?? '—'),
          _InfoTile(
            label: 'Creation time',
            value: user.metadata.creationTime?.toString() ?? '—',
          ),
          _InfoTile(
            label: 'Last sign-in',
            value: user.metadata.lastSignInTime?.toString() ?? '—',
          ),
          const SizedBox(height: 16),
          const AppSectionHeader(
            title: 'Providers',
            subtitle: 'Authentication sources linked to this account',
          ),
          const SizedBox(height: 8),
          if (providers.isEmpty)
            const AppInlineMessage(
              text: 'No providers',
              icon: Icons.info_outline,
            )
          else
            ...providers.map(
              (p) => AppSurfaceCard(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.providerId),
                  subtitle: Text(
                    [
                      if (p.email != null) 'Email: ${p.email}',
                      if (p.displayName != null) 'Name: ${p.displayName}',
                      if (p.phoneNumber != null) 'Phone: ${p.phoneNumber}',
                      if (p.uid != null) 'UID: ${p.uid}',
                    ].join('\n'),
                  ),
                  trailing: p.photoURL != null
                      ? CircleAvatar(backgroundImage: NetworkImage(p.photoURL!))
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      dense: true,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(value),
      ),
    );
  }
}
