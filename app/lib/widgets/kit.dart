import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppGlassHeader extends StatelessWidget {
  final String? eyebrow;
  final String? title;
  final Widget? leading;
  final VoidCallback? onAvatarTap;

  const AppGlassHeader({
    super.key,
    this.eyebrow,
    this.title,
    this.leading,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.margin),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.8),
        border: const Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: AppSpacing.gutter)],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null)
                  Text(
                    eyebrow!,
                    style: AppTextStyles.labelCaps.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                if (title != null)
                  Text(title!, style: AppTextStyles.headlineLgMobile),
              ],
            ),
          ),
          if (onAvatarTap != null)
            Semantics(
              button: true,
              label: 'Open settings',
              child: GestureDetector(
                onTap: onAvatarTap,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceContainerHigh,
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 18,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final Color? fill;
  final List<BoxShadow>? shadow;
  final bool glowOrb;

  const AppCard({
    super.key,
    required this.child,
    this.fill,
    this.shadow,
    this.glowOrb = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fill ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.full),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: shadow ?? AppShadows.card,
      ),
      child: Stack(
        children: [
          if (glowOrb)
            Positioned(
              top: -40,
              right: -40,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.05),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class AppPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const AppPill({
    super.key,
    required this.label,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.10)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.full),
          border: Border.all(
            color: active
                ? AppColors.primary.withValues(alpha: 0.20)
                : AppColors.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelCaps.copyWith(
            color: active ? AppColors.primary : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class AppFabMentor extends StatelessWidget {
  final VoidCallback onTap;

  const AppFabMentor({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary,
        boxShadow: AppShadows.glow,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Icon(
            Icons.smart_toy,
            color: AppColors.onPrimary,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    required this.title,
    required this.body,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.onSurfaceVariant),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: AppTextStyles.headlineMd, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class AppSectionLabel extends StatelessWidget {
  final String label;

  const AppSectionLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: AppTextStyles.labelCaps.copyWith(color: AppColors.onSurfaceVariant),
      );
}
