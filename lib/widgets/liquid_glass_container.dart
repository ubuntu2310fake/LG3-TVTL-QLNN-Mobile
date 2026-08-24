import 'package:flutter/material.dart';

class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double blurStrength;
  final double opacity;
  final BorderRadiusGeometry? borderRadius;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.blurStrength = 20.0,
    this.opacity = 0.15,
    this.borderRadius,
    this.border,
    this.padding,
    this.margin,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width, height: height,
      margin: margin, padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: borderRadius ?? BorderRadius.circular(16),
        border: border ?? Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: child,
    );
  }
}
