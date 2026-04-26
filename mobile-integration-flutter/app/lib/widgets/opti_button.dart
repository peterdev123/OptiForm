import 'package:flutter/material.dart';

enum OptiButtonVariant { filled, outlined }

class OptiButton extends StatelessWidget {
  const OptiButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = OptiButtonVariant.filled,
  });

  final String label;
  final VoidCallback? onPressed;
  final OptiButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final child = Text(label);
    switch (variant) {
      case OptiButtonVariant.outlined:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton(onPressed: onPressed, child: child),
        );
      case OptiButtonVariant.filled:
        return SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onPressed, child: child),
        );
    }
  }
}
