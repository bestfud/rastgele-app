import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFF5B8DEF);
  static const Color primarySoft = Color(0xFFEEF4FF);
  static const Color success = Color(0xFF2ECC71);
  static const Color successSoft = Color(0xFFEAFBF1);
  static const Color warning = Color(0xFFF2C94C);
  static const Color warningSoft = Color(0xFFFFF7DA);
  static const Color danger = Color(0xFFEB5757);
  static const Color dangerSoft = Color(0xFFFDECEC);
  static const Color background = Color(0xFFF7F8FA);
  static const Color card = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textLight = Color(0xFF9CA3AF);
  static const Color border = Color(0xFFE5E7EB);
}

abstract final class AppSpacing {
  static const double small = 8;
  static const double medium = 14;
  static const double large = 22;
  static const double xLarge = 24;
}

abstract final class AppRadii {
  static const double card = 18;
  static const double button = 14;
  static const double input = 16;
  static const double pill = 999;
}

List<BoxShadow> appSoftShadow(Color color) {
  return [
    BoxShadow(
      color: AppColors.textPrimary.withValues(alpha: 0.045),
      blurRadius: 22,
      offset: const Offset(0, 10),
      spreadRadius: -18,
    ),
  ];
}

class AppSegmentOption<T> {
  const AppSegmentOption({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

class AppPillSegmentedControl<T> extends StatelessWidget {
  const AppPillSegmentedControl({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.padding = const EdgeInsets.all(4),
  });

  final T value;
  final List<AppSegmentOption<T>> options;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Wrap(
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: _AppPillSegmentButton<T>(
                option: option,
                selected: option.value == value,
                onTap: () => onChanged(option.value),
              ),
            ),
        ],
      ),
    );
  }
}

class AppSurfaceSegmentOption<T> {
  const AppSurfaceSegmentOption({
    required this.value,
    required this.label,
  });

  final T value;
  final String label;
}

class AppSurfaceSegmentedControl<T> extends StatelessWidget {
  const AppSurfaceSegmentedControl({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<AppSurfaceSegmentOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: _AppSurfaceSegmentButton<T>(
                option: option,
                selected: option.value == value,
                onTap: () => onChanged(option.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _AppSurfaceSegmentButton<T> extends StatelessWidget {
  const _AppSurfaceSegmentButton({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AppSurfaceSegmentOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foregroundColor = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                  spreadRadius: -8,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Center(
              child: Text(
                option.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foregroundColor,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0.05,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppPillSegmentButton<T> extends StatelessWidget {
  const _AppPillSegmentButton({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AppSegmentOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final backgroundColor = selected ? AppColors.primarySoft : AppColors.card;
    final foregroundColor =
        selected ? AppColors.primary : AppColors.textSecondary;
    final borderColor = selected ? Colors.transparent : AppColors.border;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (option.icon != null) ...[
                Icon(option.icon, size: 16, color: foregroundColor),
                const SizedBox(width: 6),
              ],
              Text(
                option.label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.iconWidget,
  });

  final String message;
  final IconData icon;
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.background,
                shape: BoxShape.circle,
              ),
              child: iconWidget ??
                  Icon(
                    icon,
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppSkeletonBox extends StatelessWidget {
  const AppSkeletonBox({
    super.key,
    required this.height,
    this.width,
    this.radius = 14,
    this.margin,
  });

  final double height;
  final double? width;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class AppSkeletonCard extends StatelessWidget {
  const AppSkeletonCard({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget? child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: appSoftShadow(Theme.of(context).colorScheme.primary),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Card(
        child: Padding(
          padding: padding,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
