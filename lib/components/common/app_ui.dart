import 'package:flutter/material.dart';

class AppSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final bool outlined;
  final bool dense;

  const AppSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.onLongPress,
    this.color,
    this.outlined = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final background = color ?? (dense ? cs.surfaceContainerHigh : cs.surface);
    final border = outlined
        ? BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35))
        : BorderSide(color: cs.outlineVariant.withValues(alpha: 0.18));
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: border,
    );

    return Padding(
      padding: margin,
      child: Material(
        color: background,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class AppSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if ((subtitle ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final Color? iconColor;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.ctaLabel,
    this.onCta,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AppSurfaceCard(
            color: cs.surfaceContainerLow,
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 34, color: iconColor ?? cs.primary),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (ctaLabel != null && onCta != null) ...[
                  const SizedBox(height: 14),
                  FilledButton(onPressed: onCta, child: Text(ctaLabel!)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppLockState extends StatelessWidget {
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onTap;

  const AppLockState({
    super.key,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.workspace_premium,
      title: title,
      message: message,
      ctaLabel: buttonLabel,
      onCta: onTap,
    );
  }
}

class AppInlineMessage extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;

  const AppInlineMessage({
    super.key,
    required this.text,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = color ?? cs.secondary;
    return AppSurfaceCard(
      dense: true,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: tone),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tone),
            ),
          ),
        ],
      ),
    );
  }
}
