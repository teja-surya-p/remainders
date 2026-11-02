import 'package:flutter/material.dart';

import '../notifs.dart';
import '../platform/system_settings.dart';
import '../theme/app_tokens.dart';

/// One phone setting that decides whether alarms ring on time.
class ReliabilityItem {
  const ReliabilityItem({
    required this.page,
    required this.title,
    required this.ok,
    required this.okText,
    required this.problemText,
    this.steps,
  });

  final SettingsPage page;
  final String title;
  final bool ok;
  final String okText;
  final String problemText;

  /// Maker-specific steps shown while there's a problem (battery).
  final String? steps;
}

/// Checks everything that can stop or delay an alarm.
Future<List<ReliabilityItem>> checkReliability() async {
  final permissions = await Notifs.permissions();
  final device = await SystemSettings.status();
  return [
    ReliabilityItem(
      page: SettingsPage.notifications,
      title: 'Notifications',
      ok: permissions.notificationsEnabled,
      okText: 'Allowed',
      problemText:
          "Off, so reminders can't alert you. Turn on notifications for "
          'Snooze.',
    ),
    ReliabilityItem(
      page: SettingsPage.exactAlarms,
      title: 'Alarms & reminders',
      ok: permissions.exactAlarmsAllowed,
      okText: 'Allowed: alarms ring on the minute',
      problemText:
          'Not allowed, so Android may ring alarms several minutes late. '
          'Allow "Alarms & reminders" for Snooze.',
    ),
    ReliabilityItem(
      page: SettingsPage.fullScreen,
      title: 'Full-screen alarms',
      ok: device.fullScreenAllowed,
      okText: 'Allowed: alarms open over the lock screen',
      problemText:
          'Not allowed, so alarms show only as a notification. Allow '
          'full-screen notifications for Snooze.',
    ),
    ReliabilityItem(
      page: SettingsPage.battery,
      title: 'Battery',
      ok: device.batteryUnrestricted,
      okText: 'Unrestricted',
      problemText:
          'Battery saving can stop Snooze in the background and delay '
          'alarms.',
      steps: batteryStepsFor(device.manufacturer),
    ),
  ];
}

/// Where each phone maker hides the battery setting (menu names vary by
/// model and Android version).
String batteryStepsFor(String manufacturer) => switch (manufacturer) {
  'samsung' =>
    'Settings → Apps → Snooze → Battery → Unrestricted. Also make sure '
        'Snooze isn’t in "Sleeping apps" or "Deep sleeping apps" '
        '(Settings → Battery → Background usage limits).',
  'xiaomi' || 'redmi' || 'poco' =>
    'Settings → Apps → Manage apps → Snooze: turn on Autostart, and set '
        'Battery saver to "No restrictions".',
  'oneplus' || 'oppo' || 'realme' =>
    'Settings → Apps → Snooze → Battery usage: allow background activity '
        'and auto launch.',
  'vivo' || 'iqoo' =>
    'Settings → Battery → Background power consumption management → '
        'Snooze → Allow. Then Settings → Apps → Autostart → Snooze on.',
  'huawei' || 'honor' =>
    'Settings → Battery → App launch → Snooze: switch to "Manage '
        'manually" and allow auto-launch, secondary launch and running in '
        'the background.',
  'motorola' ||
  'google' => 'Settings → Apps → Snooze → App battery usage → Unrestricted.',
  _ =>
    'Settings → Apps → Snooze → Battery: choose "Unrestricted" or "Don’t '
        'optimize".',
};

/// The live checklist, refreshed whenever the user comes back from
/// Settings.
class ReliabilityList extends StatefulWidget {
  const ReliabilityList({super.key});

  @override
  State<ReliabilityList> createState() => _ReliabilityListState();
}

class _ReliabilityListState extends State<ReliabilityList>
    with WidgetsBindingObserver {
  List<ReliabilityItem>? _items;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final items = await checkReliability();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _fix(ReliabilityItem item) async {
    if (item.page == SettingsPage.notifications &&
        await Notifs.requestNotificationPermission()) {
      await _refresh();
      return;
    }
    final opened = await SystemSettings.open(item.page);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't open Settings. Open it from your phone."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final tone = AppTone.of(context);
    final textTheme = Theme.of(context).textTheme;
    final allOk = items.every((i) => i.ok);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allOk)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'All set: alarms can ring on time.',
              style: textTheme.titleSmall?.copyWith(color: tone.success),
            ),
          ),
        for (final item in items)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        item.ok
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        color: item.ok ? tone.success : tone.warning,
                        semanticLabel: item.ok ? 'OK' : 'Needs attention',
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(item.title, style: textTheme.titleSmall),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.ok ? item.okText : item.problemText,
                    style: textTheme.bodyMedium?.copyWith(
                      color: tone.mutedText,
                    ),
                  ),
                  if (!item.ok && item.steps != null) ...[
                    const SizedBox(height: 6),
                    Text(item.steps!, style: textTheme.bodyMedium),
                  ],
                  if (!item.ok)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => _fix(item),
                        child: Text(
                          item.page == SettingsPage.notifications
                              ? 'Allow'
                              : 'Open settings',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Profile → Alarm reliability.
class ReliabilityCheckPage extends StatelessWidget {
  const ReliabilityCheckPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alarm reliability')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: const [
          Text(
            'Android can delay or silence reminders unless Snooze is allowed '
            'to run them. Fix anything marked below; this page updates when '
            'you come back from Settings.',
          ),
          SizedBox(height: 16),
          ReliabilityList(),
        ],
      ),
    );
  }
}
