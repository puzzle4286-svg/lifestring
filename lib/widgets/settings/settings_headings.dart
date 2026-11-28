import 'package:flutter/material.dart';

/// The heading of a Settings group (Theme, Home-screen, Data): in the
/// accent colour and bold, so groups stand apart from their subheadings.
class SettingsHeading extends StatelessWidget {
  const SettingsHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// A subheading within a Settings group (e.g. Theme → Style): smaller,
/// italic and muted.
class SettingsSubheading extends StatelessWidget {
  const SettingsSubheading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        fontStyle: FontStyle.italic,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
