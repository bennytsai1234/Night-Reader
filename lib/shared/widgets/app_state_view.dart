import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

enum AppStateTone { neutral, error }

class AppStateAction {
  const AppStateAction({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
}

/// Shared full-page state for empty, filtered-empty, and recoverable error views.
class AppStateView extends StatelessWidget {
  const AppStateView({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.primaryAction,
    this.secondaryAction,
    this.tone = AppStateTone.neutral,
  });

  final IconData icon;
  final String title;
  final String? description;
  final AppStateAction? primaryAction;
  final AppStateAction? secondaryAction;
  final AppStateTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent =
        tone == AppStateTone.error ? scheme.error : scheme.onSurfaceVariant;
    final descriptionText = description?.trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        final verticalInset = AppSpacing.xxl * 2;
        final minHeight = constraints.hasBoundedHeight
            ? (constraints.maxHeight - verticalInset)
                  .clamp(0.0, double.infinity)
                  .toDouble()
            : 0.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Semantics(
                  container: true,
                  liveRegion: tone == AppStateTone.error,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 40, color: accent),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (descriptionText != null &&
                          descriptionText.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          descriptionText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (primaryAction != null || secondaryAction != null) ...[
                        const SizedBox(height: AppSpacing.xl),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            if (primaryAction != null)
                              _StateActionButton(
                                action: primaryAction!,
                                emphasis:
                                    tone == AppStateTone.error
                                        ? _ActionEmphasis.filled
                                        : _ActionEmphasis.outlined,
                              ),
                            if (secondaryAction != null)
                              _StateActionButton(
                                action: secondaryAction!,
                                emphasis: _ActionEmphasis.text,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _ActionEmphasis { filled, outlined, text }

class _StateActionButton extends StatelessWidget {
  const _StateActionButton({required this.action, required this.emphasis});

  final AppStateAction action;
  final _ActionEmphasis emphasis;

  @override
  Widget build(BuildContext context) {
    switch (emphasis) {
      case _ActionEmphasis.filled:
        return action.icon == null
            ? FilledButton(
              onPressed: action.onPressed,
              child: Text(action.label),
            )
            : FilledButton.icon(
              onPressed: action.onPressed,
              icon: Icon(action.icon),
              label: Text(action.label),
            );
      case _ActionEmphasis.outlined:
        return action.icon == null
            ? OutlinedButton(
              onPressed: action.onPressed,
              child: Text(action.label),
            )
            : OutlinedButton.icon(
              onPressed: action.onPressed,
              icon: Icon(action.icon),
              label: Text(action.label),
            );
      case _ActionEmphasis.text:
        return action.icon == null
            ? TextButton(onPressed: action.onPressed, child: Text(action.label))
            : TextButton.icon(
              onPressed: action.onPressed,
              icon: Icon(action.icon),
              label: Text(action.label),
            );
    }
  }
}
