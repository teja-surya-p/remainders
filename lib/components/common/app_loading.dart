import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

class AppLoadingIndicator extends StatefulWidget {
  final String? label;

  const AppLoadingIndicator({super.key, this.label});

  @override
  State<AppLoadingIndicator> createState() => _AppLoadingIndicatorState();
}

class _AppLoadingIndicatorState extends State<AppLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_controller.value);
                return Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary.withValues(alpha: 0.10 + (t * 0.15)),
                  ),
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      valueColor: AlwaysStoppedAnimation(cs.primary),
                    ),
                  ),
                );
              },
            ),
            if ((widget.label ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              AnimatedOpacity(
                duration: AppMotion.card,
                opacity: 1,
                child: Text(
                  widget.label!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
