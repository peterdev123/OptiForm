import 'package:flutter/material.dart';

class OptiCard extends StatelessWidget {
  const OptiCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: Card(
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
