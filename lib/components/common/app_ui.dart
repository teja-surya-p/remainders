import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_tokens.dart';

class AppSurfaceCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final bool outlined;
  final bool dense;
  final bool glass;

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
    this.glass = false,
  });

  @override
  State<AppSurfaceCard> createState() => _AppSurfaceCardState();
}

class _AppSurfaceCardState extends State<AppSurfaceCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = AppTone.of(context);

    final bg =
        widget.color ??
        (widget.glass
            ? tone.glassBackground
            : (widget.dense
                  ? cs.secondary.withValues(alpha: 0.64)
                  : cs.surface));

    final border = widget.outlined
        ? BorderSide(color: tone.cardBorder, width: 1)
        : BorderSide(color: tone.cardBorder.withValues(alpha: 0.65));

    return Padding(
      padding: widget.margin,
      child: AnimatedScale(
        duration: AppMotion.micro,
        curve: AppMotion.standard,
        scale: _pressed ? 0.985 : 1,
        child: AnimatedContainer(
          duration: AppMotion.card,
          curve: AppMotion.standard,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.fromBorderSide(border),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              onHighlightChanged: (value) => setState(() => _pressed = value),
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
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
    final tone = AppTone.of(context);
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
                Text(
                  subtitle!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tone.mutedText),
                ),
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
    final tone = AppTone.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: AppSurfaceCard(
            dense: true,
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: cs.secondary.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, size: 28, color: iconColor ?? cs.primary),
                ),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: tone.mutedText),
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
      icon: Icons.workspace_premium_rounded,
      title: title,
      message: message,
      ctaLabel: buttonLabel,
      onCta: onTap,
      iconColor: Theme.of(context).colorScheme.primary,
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
    final tone = AppTone.of(context);
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? tone.mutedText;
    final bg = cs.secondary.withValues(alpha: 0.56);

    return AppSurfaceCard(
      dense: true,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
