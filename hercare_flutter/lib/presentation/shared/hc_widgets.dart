import 'package:flutter/material.dart';

import '../../core/theme/theme_ext.dart';

/// Small shared building blocks so every screen uses the same spacing,
/// corner radius, shadows and section titles.

/// Section title with an optional action ("View all") at the end.
class HcSectionHeader extends StatelessWidget {
  const HcSectionHeader(
      {super.key,
      required this.title,
      this.subtitle,
      this.actionLabel,
      this.onAction,
      this.trailing});

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 18)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: context.hcTextSecondary)),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(48, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(actionLabel!,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.primary)),
          ),
      ],
    );
  }
}

/// Rounded, softly shadowed surface. Pass [onTap] to make it tappable with a
/// ripple that stays inside the rounded corners.
class HcCard extends StatelessWidget {
  const HcCard(
      {super.key,
      required this.child,
      this.onTap,
      this.padding = const EdgeInsets.all(18),
      this.color,
      this.gradient,
      this.radius = 24,
      this.border});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Gradient? gradient;
  final double radius;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? context.hcSurface) : null,
        gradient: gradient,
        borderRadius: shape,
        border: border ??
            (context.isDark ? Border.all(color: context.hcOutline) : null),
        boxShadow: context.hcSoftShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Rounded square icon on a pastel tint.
class HcIconBadge extends StatelessWidget {
  const HcIconBadge(
      {super.key,
      required this.icon,
      required this.color,
      required this.background,
      this.size = 44});

  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: context.isDark ? color.withValues(alpha: 0.18) : background,
          borderRadius: BorderRadius.circular(size * 0.34),
        ),
        child: Icon(icon, color: color, size: size * 0.52),
      );
}

/// Small rounded status label, e.g. "DUE" or "Saved today".
class HcPill extends StatelessWidget {
  const HcPill(
      {super.key, required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: context.isDark ? 0.2 : 0.12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
}
