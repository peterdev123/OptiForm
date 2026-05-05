import 'package:flutter/material.dart';

enum OptiButtonVariant { filled, outlined }

class OptiButton extends StatelessWidget {
  const OptiButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = OptiButtonVariant.filled,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final OptiButtonVariant variant;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spinnerColor = variant == OptiButtonVariant.filled
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.primary;

    final Widget content = loading
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: spinnerColor,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          )
        : Text(label);

    switch (variant) {
      case OptiButtonVariant.outlined:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: loading ? null : onPressed,
            child: content,
          ),
        );
      case OptiButtonVariant.filled:
        return SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: loading ? null : onPressed,
            child: content,
          ),
        );
    }
  }
}
