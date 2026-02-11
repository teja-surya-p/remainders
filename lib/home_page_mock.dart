import 'package:flutter/material.dart';

class HomePageMock extends StatelessWidget {
  const HomePageMock({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reminders'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Today'),
              Tab(text: 'Upcoming'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          child: const Icon(Icons.add),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _ReminderList(
                header: _TodaySummaryCard(color: cs.primaryContainer),
                items: List.generate(
                  6,
                  (i) => _ReminderItem(
                    title: 'Reminder #${i + 1}',
                    subtitle: i.isEven ? '9:00 AM' : '3:30 PM',
                    done: i == 1,
                  ),
                ),
              ),
              _ReminderList(
                header: const _InfoCard(
                  icon: Icons.calendar_month,
                  title: 'Upcoming reminders',
                  subtitle: 'Plan ahead - schedule what’s next.',
                ),
                items: List.generate(
                  8,
                  (i) => _ReminderItem(
                    title: 'Upcoming #${i + 1}',
                    subtitle: 'Feb ${10 + i}, 10:00 AM',
                    done: false,
                  ),
                ),
              ),
              _ReminderList(
                header: const _InfoCard(
                  icon: Icons.check_circle,
                  title: 'Completed',
                  subtitle: 'Nice. You’re making progress.',
                ),
                items: List.generate(
                  5,
                  (i) => _ReminderItem(
                    title: 'Done #${i + 1}',
                    subtitle: 'Yesterday',
                    done: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderList extends StatelessWidget {
  final Widget header;
  final List<_ReminderItem> items;

  const _ReminderList({required this.header, required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        header,
        const SizedBox(height: 16),
        ...items.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ReminderTile(
              title: e.title,
              subtitle: e.subtitle,
              done: e.done,
            ),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _ReminderItem {
  final String title;
  final String subtitle;
  final bool done;
  _ReminderItem({required this.title, required this.subtitle, required this.done});
}

class _TodaySummaryCard extends StatelessWidget {
  final Color color;
  const _TodaySummaryCard({required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.notifications_active),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You have 3 reminders today',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text('Tap + to add a new reminder.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoCard({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool done;

  const _ReminderTile({
    required this.title,
    required this.subtitle,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(done ? Icons.check_circle : Icons.radio_button_unchecked),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
