import 'package:flutter/material.dart';

class AppLoadingIndicator extends StatelessWidget {
  final String? label;

  const AppLoadingIndicator({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.8),
            ),
            if ((label ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                label!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AppLoadingScaffold extends StatelessWidget {
  final String? label;

  const AppLoadingScaffold({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: AppLoadingIndicator(label: label));
  }
}
